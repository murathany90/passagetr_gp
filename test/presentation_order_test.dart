import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/presentation_order.dart';

void main() {
  test('deterministic word shuffle paginates without duplicates or omissions',
      () {
    final words = List<String>.generate(
      5314,
      (index) => 'word-${index.toString().padLeft(4, '0')}',
    );
    final first = orderForPresentation<String>(
      words,
      order: PresentationOrder.mixed,
      hasSearchQuery: false,
      sessionSeed: 24831,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );
    final repeat = orderForPresentation<String>(
      words,
      order: PresentationOrder.mixed,
      hasSearchQuery: false,
      sessionSeed: 24831,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );

    expect(first, repeat);
    expect(_allPages(first, 72).toSet(), words.toSet());
    expect(_allPages(first, 72), hasLength(words.length));

    final searched = orderForPresentation<String>(
      words.reversed,
      order: PresentationOrder.mixed,
      hasSearchQuery: true,
      sessionSeed: 24831,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );
    expect(searched, words);
  });

  test(
      'deterministic reading shuffle paginates without duplicates or omissions',
      () {
    final readings = List<String>.generate(
      678,
      (index) => 'reading-${index.toString().padLeft(4, '0')}',
    );
    final first = orderForPresentation<String>(
      readings,
      order: PresentationOrder.mixed,
      hasSearchQuery: false,
      sessionSeed: 9137,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );
    final repeat = orderForPresentation<String>(
      readings,
      order: PresentationOrder.mixed,
      hasSearchQuery: false,
      sessionSeed: 9137,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );

    expect(first, repeat);
    expect(_allPages(first, 48).toSet(), readings.toSet());
    expect(_allPages(first, 48), hasLength(readings.length));

    final alphabetical = orderForPresentation<String>(
      readings.reversed,
      order: PresentationOrder.alphabetical,
      hasSearchQuery: false,
      sessionSeed: 9137,
      alphabeticalComparator: (left, right) => left.compareTo(right),
    );
    expect(alphabetical, readings);
  });
}

List<T> _allPages<T>(List<T> items, int pageSize) => <T>[
      for (var start = 0; start < items.length; start += pageSize)
        ...items.skip(start).take(pageSize),
    ];
