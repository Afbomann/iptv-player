import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../platform/backup_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'library.dart';
import 'settings.dart';
import 'guide.dart';
import 'live_categories.dart';
import 'recordings.dart';
import 'backup_transfer.dart';
import 'backup_input_lock.dart';
import '../platform/device.dart';

class LumenApp extends ConsumerWidget {
  const LumenApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final prefs = app.current?.preferences ?? {};
    return MaterialApp(
      key: ValueKey(app.current?.id),
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(
        accent: Color(prefs['accent'] ?? limeColor.toARGB32()),
        light: prefs['theme'] == 'light',
        compact: prefs['density'] == 'compact',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear((prefs['textScale'] ?? 1.0).toDouble()),
        ),
        child: Stack(
          children: [
            BackupInputLock(busy: app.backupBusy, child: child!),
            if (app.backupBusy)
              Positioned.fill(
                child: Material(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        const Text(
                          'Processing backup… Keep the app open.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      home: app.current == null
          ? const AccountGate()
          : AppShell(key: ValueKey(app.current!.id)),
    );
  }
}

class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({super.key});
  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<AccountGate> {
  final name = TextEditingController(), password = TextEditingController();
  String? selected, error;
  String mode = 'profiles';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final app = ref.read(appProvider);
    try {
      if (app.profiles.isEmpty) {
        await app.createAdmin(name.text, password.text);
      } else if (mode == 'manual') {
        await app.loginByName(name.text, password.text);
      } else {
        final candidates = app.profiles
            .where((p) => mode == 'admin' ? p.admin : p.discoverable)
            .toList();
        if (candidates.isEmpty) {
          throw const FormatException('Choose another sign-in method.');
        }
        await app.login(
          candidates.where((p) => p.id == selected).firstOrNull ??
              candidates.first,
          password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    await perform(context, _restore);
  }

  Future<void> _restore() async {
    if (isAppleTV) {
      await transferBackup(context, ref.read(appProvider));
      return;
    }
    final file = await FilePicker.platform.pickFiles(
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: ['lumen'],
    );
    if (file == null || !mounted) return;
    var secret = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore your Lumen'),
        content: TextField(
          onChanged: (value) => secret = value,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Backup password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      setState(() => busy = true);
      await perform(
        context,
        () async => ref
            .read(appProvider)
            .restoreBackup(await readBackupFile(file.files.single), secret),
      );
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final setup = app.profiles.isEmpty;
    final listed = app.profiles.where((p) => p.discoverable).toList();
    final picked =
        listed.where((p) => p.id == selected).firstOrNull ?? listed.firstOrNull;
    final usesPin = !setup && mode == 'profiles' && picked?.usesPin == true;
    void switchMode(String next) => setState(() {
      mode = next;
      password.clear();
      name.clear();
      error = null;
    });
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            if (box.maxWidth > 1000)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(56),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xff344b32),
                        Color(0xff1c2a21),
                        Color(0xff111c17),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Brand(),
                      const Spacer(),
                      const Eyebrow('Your channels. Your space.'),
                      const SizedBox(height: 24),
                      const Text(
                        'Everything you love.\nA little closer.',
                        style: TextStyle(
                          fontFamily: 'Newsreader',
                          fontSize: 68,
                          height: 1.04,
                          color: Color(0xffeef2dd),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Live moments, late-night discoveries, and familiar favorites.\nOne thoughtfully personal place to watch.',
                        style: TextStyle(
                          color: Color(0xffbecbb6),
                          fontSize: 16,
                          height: 1.8,
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: const [
                          Text(
                            '◉  DEVICE-LOCAL',
                            style: TextStyle(fontSize: 11, letterSpacing: 1.5),
                          ),
                          Text(
                            '◈  MADE FOR YOUR SCREEN',
                            style: TextStyle(fontSize: 11, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (box.maxWidth <= 1000) ...[
                            const Brand(),
                            const SizedBox(height: 64),
                          ],
                          Eyebrow(
                            setup
                                ? 'Welcome to your first frame'
                                : 'Make yourself at home',
                          ),
                          const SizedBox(height: 18),
                          Text(
                            setup ? 'A space of your own.' : 'Who’s watching?',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            setup
                                ? 'Create your administrator account. You’ll manage playlists, profiles, and parental controls on this device.'
                                : 'Sign in to your local profile to pick up where you left off.',
                            style: const TextStyle(
                              color: mutedColor,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (setup)
                            TextField(
                              controller: name,
                              autofocus: true,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'Administrator name',
                              ),
                              onSubmitted: (_) => submit(),
                            )
                          else if (mode == 'admin')
                            const Text('Administrator sign-in')
                          else if (mode == 'manual')
                            TextField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'Account name',
                              ),
                              onSubmitted: (_) => submit(),
                            )
                          else if (listed.isEmpty)
                            const Text(
                              'No discoverable profiles. Sign in by name or as administrator below.',
                            )
                          else
                            DropdownButtonFormField<String>(
                              key: ValueKey(picked?.id),
                              initialValue: picked?.id,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Profile',
                              ),
                              items: listed
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() {
                                      selected = v;
                                      password.clear();
                                      error = null;
                                    }),
                            ),
                          const SizedBox(height: 16),
                          TextField(
                            key: ValueKey(usesPin),
                            controller: password,
                            obscureText: true,
                            keyboardType: usesPin
                                ? TextInputType.number
                                : TextInputType.text,
                            inputFormatters: usesPin
                                ? [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(8),
                                  ]
                                : null,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: [
                              setup
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: !setup && mode == 'manual'
                                  ? 'PIN or password'
                                  : usesPin
                                  ? 'PIN'
                                  : 'Password',
                              helperText: setup
                                  ? 'At least 10 characters'
                                  : null,
                            ),
                            onSubmitted: (_) => submit(),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  busy ||
                                      (!setup &&
                                          mode == 'profiles' &&
                                          listed.isEmpty)
                                  ? null
                                  : submit,
                              child: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      setup
                                          ? 'Create your space →'
                                          : 'Start watching →',
                                    ),
                            ),
                          ),
                          if (!setup) ...[
                            if (mode != 'profiles')
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => switchMode('profiles'),
                                child: const Text('Choose a profile'),
                              ),
                            if (mode != 'manual')
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => switchMode('manual'),
                                child: const Text('Sign in by account name'),
                              ),
                            if (mode != 'admin')
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => switchMode('admin'),
                                child: const Text('Administrator sign-in'),
                              ),
                          ],
                          if (setup) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: busy ? null : restore,
                              child: const Text(
                                'Already have a backup? Restore it',
                              ),
                            ),
                          ],
                          const SizedBox(height: 34),
                          const Text(
                            'Your library stays on this device.\nNo subscription or content is included.',
                            style: TextStyle(
                              fontSize: 12,
                              color: mutedColor,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int selected = 0;
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  final nav = const [
    (Icons.home_outlined, 'For you'),
    (Icons.live_tv_rounded, 'Live TV'),
    (Icons.calendar_view_week_outlined, 'TV guide'),
    (Icons.movie_outlined, 'Movies'),
    (Icons.video_library_outlined, 'Series'),
    (Icons.star_outline_rounded, 'Favorites'),
    (Icons.fiber_manual_record_outlined, 'Recordings'),
    (Icons.tune_rounded, 'Settings'),
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(appProvider).refreshDue();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      PaintingBinding.instance.imageCache.clear();
      unawaited(ref.read(appProvider).store.releaseMemory());
    }
  }

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    unawaited(ref.read(appProvider).store.releaseMemory());
  }

  void navigate(int index) {
    debounce?.cancel();
    setState(() {
      selected = index;
      query = '';
      search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final p = app.current!;
    final wide = app.isTV || MediaQuery.sizeOf(context).width >= 1000;
    final content = query.isNotEmpty
        ? CatalogPage(
            key: ValueKey('search:$selected:$query'),
            title: selected == 3
                ? 'Search movies'
                : selected == 4
                ? 'Search series'
                : selected == 1 || selected == 2
                ? 'Search live TV'
                : 'Search results',
            kind: selected == 3
                ? MediaKind.movie
                : selected == 4
                ? MediaKind.series
                : selected == 1 || selected == 2
                ? MediaKind.live
                : null,
            favorites: selected == 5,
            query: query,
          )
        : switch (selected) {
            0 => HomePage(onNavigate: navigate),
            1 => const LiveCategoriesPage(),
            2 => const GuidePage(),
            3 => const CatalogPage(title: 'Movies', kind: MediaKind.movie),
            4 => const CatalogPage(title: 'Series', kind: MediaKind.series),
            5 => const CatalogPage(title: 'Your favorites', favorites: true),
            6 => const RecordingsPage(),
            _ => const SettingsPage(),
          };
    Widget navigation() => SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(26, 32, 20, 36),
            child: Brand(small: true),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 28, bottom: 12),
            child: Text(
              'YOUR SPACE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: mutedColor,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: nav.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selected: selected == i,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .13),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  leading: Icon(nav[i].$1, size: 21),
                  title: Text(
                    nav[i].$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    navigate(i);
                    if (!wide) Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  p.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                p.admin ? 'Administrator' : 'Local profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.logout, size: 18),
              onTap: app.logout,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      drawer: wide ? null : Drawer(child: navigation()),
      body: Row(
        children: [
          if (wide)
            Container(
              width: 225,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
              child: navigation(),
            ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 36 : 12,
                      18,
                      wide ? 36 : 16,
                      14,
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          Builder(
                            builder: (c) => IconButton(
                              tooltip: 'Navigation',
                              onPressed: () => Scaffold.of(c).openDrawer(),
                              icon: const Icon(Icons.menu),
                            ),
                          ),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: TextField(
                              controller: search,
                              decoration: const InputDecoration(
                                hintText: 'Find a channel, film, or series',
                                prefixIcon: Icon(Icons.search, size: 20),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              onChanged: (v) {
                                debounce?.cancel();
                                debounce = Timer(
                                  const Duration(milliseconds: 250),
                                  () => setState(() => query = v.trim()),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Refresh playlists and guide',
                          onPressed: app.refreshing
                              ? null
                              : () => app.refreshDue(force: true),
                          icon: const Icon(Icons.sync),
                        ),
                      ],
                    ),
                  ),
                  if (app.refreshing)
                    const LinearProgressIndicator(minHeight: 2),
                  if (app.activity != null)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        app.activity!,
                        style: const TextStyle(fontSize: 11, color: mutedColor),
                      ),
                    ),
                  if (app.refreshError != null)
                    MaterialBanner(
                      content: Text(
                        app.refreshError!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            app.refreshError = null;
                            app.changed();
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  if (!app.refreshing && app.refreshSummary != null)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        app.refreshSummary!,
                        style: const TextStyle(fontSize: 11, color: mutedColor),
                      ),
                    ),
                  Expanded(child: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
