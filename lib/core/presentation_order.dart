import 'dart:math';

enum PresentationOrder { mixed, alphabetical }

int createPresentationSeed({int? previousSeed}) {
  var seed = Random().nextInt(1 << 31);
  if (seed == previousSeed) {
    seed = (seed + 1) % (1 << 31);
  }
  return seed;
}

List<T> orderForPresentation<T>(
  Iterable<T> source, {
  required PresentationOrder order,
  required bool hasSearchQuery,
  required int sessionSeed,
  required Comparator<T> alphabeticalComparator,
}) {
  final items = List<T>.of(source);
  if (hasSearchQuery || order == PresentationOrder.alphabetical) {
    items.sort(alphabeticalComparator);
  } else {
    items.shuffle(Random(sessionSeed));
  }
  return items;
}
