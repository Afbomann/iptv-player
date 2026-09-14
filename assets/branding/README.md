# Lumen brand assets

Generated with the built-in image-generation tool. The selected direction is a restrained pale-lime L/play mark on charcoal; interface controls use the profile's chosen accent independently of this fixed brand artwork.

Masters: `lumen-icon.png` and `lumen-banner.png`. Platform images are deterministic size exports, not independently redrawn logos. Run `dart run tooling/brand_assets.dart` after replacing the masters. This updates Android launcher/TV/splash artwork, iOS icons/splash images, tvOS layered icons/top shelf, Windows ICO, web/PWA icons. Linux packaging consumes the web icon.

## Generation prompts

Icon (built-in generation):

Use case: logo-brand. Asset type: production app icon master for Lumen, an IPTV streaming player with a refined dark charcoal and pale lime visual identity. Create one original minimal geometric symbol, a folded ribbon forming an L with a subtle rightward play-cutout in its negative space. Flat pale lime #d5ed9c mark on a perfectly uniform dark charcoal #101310 square background. One centered symbol occupying the central 60 percent of the canvas, generous even margins for circular/maskable icon crops. Strong clear silhouette readable at 24px. Crisp vector-like edges rendered as a high-resolution square PNG. No text, no wordmark, no gradients, no glow, no mockup, no device, no shadows, no border, no extra symbols. Output a single finished square app icon.

Banner (built-in generation using the icon as reference):

Use case: logo-brand. Asset type: Lumen TV launcher banner and Apple TV top shelf brand artwork. Use the supplied Lumen icon as the identity reference: preserve the exact L/play symbol silhouette and pale lime color. Create a clean very wide landscape banner, 16:9 framing, uniformly dark charcoal #101713 background. Center a compact horizontal lockup consisting of that symbol and the lowercase word "lumen" in bold refined sans-serif typography. The entire lockup should occupy the central 55 percent of image width and central 40 percent of height, with ample empty dark margins for safe cropping. Exact text: "lumen" only. No slogan, no additional symbols, no glow, no scene, no mockup, no rounded outer frame, no watermarks. Crisp professional brand artwork.
