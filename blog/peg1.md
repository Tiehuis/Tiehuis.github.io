# PEG Grammar for Chord Notation
<div class="published"><time datetime="2017-12-17">17 Dec 2017</time></div>

Recently I was looking for a grammar to catagorize music chords but was
surprised that there weren't any decent ones around.

The following is a PEG grammar which categorizes the most common cases for
standard Jazz notation. There are a few missing edge cases (e.g. 7sus4).

I'm still unsure whether a full grammar is worthwhile due to the many edge
cases. I've written a parser previously using [parser
combinators](https://github.com/tiehuis/quartic/blob/master/src/parser.rs)
which was fairly straight-forward.

You can find an online peg parser generator [here](https://pegjs.org/online).

```text
PolyChord          = Chord ('|' Chord)?
Chord              = Chord1 / Chord2 / Chord3 / Chord4

Chord1             = Note Special ChordUpper
Chord2             = Note ThirdSeventh Extended? ChordUpper
Chord3             = Note Third? Sixth ChordUpper
Chord4             = Note Third? Extended? ChordUpper

ChordUpper         = Addition? Alterations? Slash?
ThirdSeventh       = Augmented / Diminished
Augmented          = 'aug' / '+'
Diminished         = 'dim' / 'o' / 'ø'

Special            = '5' / 'sus2' / 'sus4'
Sixth              = '6' / '6/9'

Third              = (MajorThird !Extended) / MinorThird
MajorThird         = 'Maj' / 'M' / 'Δ'
MinorThird         = 'min' / 'm' / '-'

Extended           = ExtendedQuality? ExtendedInterval
ExtendedQuality    = MajorThird / 'dom'
ExtendedInterval   = '7' / '9' / '11' / '13'

Alterations        = Alteration / AlterationList
AlterationList     = '(' Alteration (',' Alteration)* ')'
Alteration         = Accidental AlterationInterval
AlterationInterval = '4' / '5' / '9' / '11' / '13'

Addition           = 'add' ('2' / '4' / '6')

Slash              = '/' Note Accidental?

Note               = [A-G] Accidental*
Accidental         = [b#]
```
