# Plugin demos

Four looping GIFs, captured from the desktop KOReader app. Each is
720 × 1100 pixels.

- [Text](tap-to-top-text.gif): the original two taps bring text lines to the
  top. Then a heading appears near the bottom with only part of its paragraph
  visible. Tapping that heading brings the entire passage into view, including
  its ending. The text stays the same size.
- [Images and PDFs](tap-to-top-images-pdf.gif): both figures belong to one
  raster image. A tap halfway down that image brings the lower figure and its
  explanation into view together. In the second example, a tap in the whitespace
  just above a table brings the table and both explanatory paragraphs into view.
  Both taps use their exact vertical position.
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
shown as captured, with short dissolves between examples and when each GIF loops.

The sample text, illustrations, illustrative route data, and small demonstration
dictionary were created for these demos. The dictionary popup uses KOReader's real
lookup of the word "attention" in that sample StarDict dictionary.
