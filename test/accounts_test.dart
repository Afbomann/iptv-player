import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:lumen_iptv/core/controller.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/data/database.dart';

class TestAccounts extends AppController {
  TestAccounts(super.store);
  @override
  Future<void> refreshDue({bool startup = false, bool force = false}) async {}
}

void main() {
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  test(
    'Administrator creates PIN users; wrong PINs are throttled and reset clears lockout',
    () async {
      final store = LibraryStore(
        LumenDatabase(NativeDatabase.memory()),
        SecretKey(List.filled(32, 7)),
      );
      final app = TestAccounts(store);
      const admin = Profile(
        id: 'admin',
        name: 'Admin',
        passwordHash: 'existing admin hash',
        admin: true,
      );
      try {
        await store.saveProfile(admin);
        app.profiles = [admin];
        app.current = admin;
        await app.createUser('Viewer', '0042');
        var viewer = (await store.profiles()).singleWhere((p) => !p.admin);
        expect(viewer.usesPin, isTrue);
        expect(viewer.discoverable, isTrue);
        expect(admin.discoverable, isFalse);
        await app.setDiscoverable(viewer, false);
        viewer = (await store.profiles()).singleWhere((p) => !p.admin);
        expect(viewer.discoverable, isFalse);
        await expectLater(app.setDiscoverable(admin, true), throwsStateError);
        expect(viewer.passwordHash, isNot(contains('0042')));
        app.logout();
        await app.loginByName(' viewer ', '0042');
        expect(app.current?.id, viewer.id);
        await expectLater(
          app.createUser('Unauthorized', '1234'),
          throwsStateError,
        );
        await expectLater(app.resetUserPin(viewer, '5678'), throwsStateError);
        await expectLater(app.setDiscoverable(viewer, true), throwsStateError);
        app.logout();
        for (var i = 0; i < 5; i++) {
          await expectLater(app.login(viewer, '9999'), throwsFormatException);
        }
        await expectLater(
          app.login(viewer, '0042'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Too many'),
            ),
          ),
        );
        app.current = admin;
        await app.resetUserPin(viewer, '0055');
        await expectLater(app.resetUserPin(admin, '1234'), throwsStateError);
        expect(
          (await store.profiles()).singleWhere((p) => p.admin).passwordHash,
          admin.passwordHash,
        );
        viewer = (await store.profiles()).singleWhere((p) => !p.admin);
        app.logout();
        await app.login(viewer, '0055');
        expect(app.current?.id, viewer.id);
      } finally {
        app.dispose();
        await store.db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Legacy profiles keep passwords and administrator never uses PIN mode',
    () {
      final legacy = Profile.fromJson({
        'id': 'old',
        'name': 'Old',
        'passwordHash': 'hash',
      });
      expect(legacy.usesPin, isFalse);
      final admin = Profile.fromJson({
        ...legacy.toJson(),
        'admin': true,
        'pin': true,
      });
      expect(admin.usesPin, isFalse);
      expect(Profile.fromJson({...admin.toJson(), 'discoverable': true}).discoverable, isFalse);
      expect(legacy.discoverable, isTrue);
      expect(admin.toJson()['pin'], isFalse);
      final viewer = Profile.fromJson({...legacy.toJson(), 'pin': true});
      expect(Profile.fromJson(viewer.toJson()).usesPin, isTrue);
    },
  );
}
