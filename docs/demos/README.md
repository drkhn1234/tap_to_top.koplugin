# Plugin demos

Four looping GIFs, captured from the desktop KOReader app. Each is
720 × 1100 pixels and under 700 KiB. The text and PDF demos use Tap to top
v1.3.6; the highlight and dictionary demos use v1.4.0.

- [Text](tap-to-top-text.gif): two successive single taps bring the tapped
  text lines to the top of the screen.
- [Images and PDFs](tap-to-top-images-pdf.gif): an interior point in an image
  moves to the top, followed by a text line on the next visible PDF page.
- [Conflicting tap actions](tap-to-top-conflicting-actions.gif): double tap
  is selected by default for saved highlights; two quick taps open the
  highlight menu. The unused movement threshold appears gray.
- [Dictionary lookup inside highlights](tap-to-top-highlight-dictionary.gif):
  assign long press to saved highlights, then hold a word inside a highlighted
  passage, move past the 32 px threshold within that word, and release to open
  its dictionary entry. The threshold row is active with a long-press binding.

The reading screens and menus are actual KOReader captures. Captions, teal
tap indicators, and alignment markers are added for clarity. The plugin
produces the scrolling and opens the highlight menu. Screen changes are
shown as captured, with a short dissolve when each GIF loops.

The sample text, landscape illustration, and small demonstration dictionary
were created for these demos. The dictionary popup uses KOReader's real
lookup of the word "attention" in that sample StarDict dictionary.
