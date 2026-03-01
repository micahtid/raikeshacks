/// Generates deterministic anonymous names and emojis for connections
/// that haven't been mutually accepted yet.
library;

const _adjectives = [
  'Crazy', 'Happy', 'Sneaky', 'Brave', 'Chill', 'Wild', 'Funky', 'Cosmic',
  'Lucky', 'Zippy', 'Dizzy', 'Jazzy', 'Witty', 'Groovy', 'Quirky', 'Snappy',
  'Breezy', 'Nifty', 'Peppy', 'Plucky', 'Spunky', 'Zany', 'Goofy', 'Mighty',
  'Sly', 'Swift', 'Bold', 'Clever', 'Daring', 'Eager', 'Fierce', 'Keen',
  'Noble', 'Rapid', 'Sharp', 'Steady', 'Vivid', 'Warm', 'Bright', 'Calm',
];

const _animals = [
  'Cow', 'Fox', 'Owl', 'Cat', 'Dog', 'Bear', 'Wolf', 'Hawk',
  'Panda', 'Tiger', 'Eagle', 'Otter', 'Koala', 'Sloth', 'Raven', 'Moose',
  'Dolphin', 'Falcon', 'Parrot', 'Turtle', 'Penguin', 'Rabbit', 'Monkey', 'Gecko',
  'Badger', 'Bison', 'Crane', 'Drake', 'Finch', 'Goose', 'Heron', 'Ibis',
  'Jaguar', 'Kiwi', 'Lemur', 'Manta', 'Newt', 'Okapi', 'Puma', 'Quail',
];

const _emojis = [
  '\u{1F431}', '\u{1F436}', '\u{1F43B}', '\u{1F98A}', '\u{1F989}', // cat, dog, bear, fox, owl
  '\u{1F43C}', '\u{1F42F}', '\u{1F985}', '\u{1F9A6}', '\u{1F428}', // panda, tiger, eagle, otter, koala
  '\u{1F9A5}', '\u{1F427}', '\u{1F430}', '\u{1F435}', '\u{1F98E}', // sloth, penguin, rabbit, monkey, gecko
  '\u{1F42C}', '\u{1F99C}', '\u{1F422}', '\u{1F987}', '\u{1F40D}', // dolphin, parrot, turtle, bat, snake
  '\u{1F984}', '\u{1F981}', '\u{1F99D}', '\u{1F994}', '\u{1F43A}', // unicorn, lion, raccoon, hedgehog, wolf
  '\u{1F438}', '\u{1F419}', '\u{1F41D}', '\u{1F98B}', '\u{1F40A}', // frog, octopus, bee, butterfly, croc
];

/// Returns a deterministic anonymous name for a connection.
/// Uses the connection ID as a seed so the name stays stable.
String anonymousName(String connectionId) {
  final hash = connectionId.hashCode.abs();
  final adj = _adjectives[hash % _adjectives.length];
  final animal = _animals[(hash ~/ _adjectives.length) % _animals.length];
  return '$adj $animal';
}

/// Returns a deterministic emoji "avatar" for a connection.
String anonymousEmoji(String connectionId) {
  final hash = connectionId.hashCode.abs();
  return _emojis[hash % _emojis.length];
}
