class ContentPack {
  const ContentPack({
    required this.id,
    required this.name,
    required this.wordCount,
  });

  final String id;
  final String name;
  final int wordCount;

  factory ContentPack.fromJson(Map<String, Object?> json) => ContentPack(
        id: json['id']! as String,
        name: json['name']! as String,
        wordCount: json['wordCount']! as int,
      );
}

class WordEntry {
  const WordEntry({
    required this.id,
    required this.packId,
    required this.enWord,
    required this.trMeaning,
    required this.pos,
    required this.exampleEn,
    this.exampleTr,
    this.synonymsRaw,
    this.antonymsRaw,
    this.notes,
    this.level,
    this.tags = const <String>[],
  });

  final String id;
  final String packId;
  final String enWord;
  final String trMeaning;
  final String pos;
  final String exampleEn;
  final String? exampleTr;
  final String? synonymsRaw;
  final String? antonymsRaw;
  final String? notes;
  final String? level;
  final List<String> tags;

  factory WordEntry.fromJson(Map<String, Object?> json) => WordEntry(
        id: json['id']! as String,
        packId: json['packId']! as String,
        enWord: json['enWord']! as String,
        trMeaning: json['trMeaning']! as String,
        pos: json['pos']! as String,
        exampleEn: json['exampleEn']! as String,
        exampleTr: json['exampleTr'] as String?,
        synonymsRaw: json['synonymsRaw'] as String?,
        antonymsRaw: json['antonymsRaw'] as String?,
        notes: json['notes'] as String?,
        level: json['level'] as String?,
        tags: _stringList(json['tags']),
      );
}

class DictionaryEntry {
  const DictionaryEntry({
    required this.id,
    required this.enWord,
    required this.normalizedKey,
    required this.trMeaning,
    this.pos,
  });

  final String id;
  final String enWord;
  final String normalizedKey;
  final String trMeaning;
  final String? pos;

  factory DictionaryEntry.fromJson(Map<String, Object?> json) =>
      DictionaryEntry(
        id: json['id']! as String,
        enWord: json['enWord']! as String,
        normalizedKey: json['normalizedKey']! as String,
        trMeaning: json['trMeaning']! as String,
        pos: json['pos'] as String?,
      );
}

class DictionaryShard {
  const DictionaryShard({
    required this.prefix,
    required this.rangeStart,
    required this.rangeEnd,
    required this.file,
    required this.recordCount,
    required this.checksum,
    required this.sizeBytes,
  });

  final String prefix;
  final String rangeStart;
  final String rangeEnd;
  final String file;
  final int recordCount;
  final String checksum;
  final int sizeBytes;

  factory DictionaryShard.fromJson(Map<String, Object?> json) =>
      DictionaryShard(
        prefix: json['prefix']! as String,
        rangeStart: json['rangeStart']! as String,
        rangeEnd: json['rangeEnd']! as String,
        file: json['file']! as String,
        recordCount: json['recordCount']! as int,
        checksum: json['checksum']! as String,
        sizeBytes: json['sizeBytes']! as int,
      );
}

class ReadingPassage {
  const ReadingPassage({
    required this.id,
    required this.packId,
    required this.title,
    required this.sentenceCount,
    this.level,
    this.category,
    this.tags = const <String>[],
    this.summary,
    this.summaryTr,
    this.summaryType,
    this.sourceNumber,
    this.displayTitle,
    this.turkishTitle,
    this.wordCount = 0,
    this.estimatedReadingMinutes = 0,
    this.author,
    this.durationMinutes,
    this.coverAsset,
    this.coverAltText,
    this.file,
  });

  final String id;
  final String packId;
  final String title;
  final int sentenceCount;
  final String? level;
  final String? category;
  final List<String> tags;
  final String? summary;
  final String? summaryTr;
  final String? summaryType;
  final String? sourceNumber;
  final String? displayTitle;
  final String? turkishTitle;
  final int wordCount;
  final int estimatedReadingMinutes;
  final String? author;
  final int? durationMinutes;
  final String? coverAsset;
  final String? coverAltText;
  final String? file;

  factory ReadingPassage.fromJson(Map<String, Object?> json) => ReadingPassage(
        id: json['id']! as String,
        packId: json['packId']! as String,
        title: json['title']! as String,
        sentenceCount: (json['sentenceCount'] as int?) ?? 0,
        level: json['level'] as String?,
        category: json['category'] as String?,
        tags: _stringList(json['tags']),
        summary: json['summary'] as String?,
        summaryTr: json['summaryTr'] as String?,
        summaryType: json['summaryType'] as String?,
        sourceNumber: json['sourceNumber'] as String?,
        displayTitle: json['displayTitle'] as String?,
        turkishTitle: json['turkishTitle'] as String?,
        wordCount: (json['wordCount'] as int?) ?? 0,
        estimatedReadingMinutes: (json['estimatedReadingMinutes'] as int?) ??
            (json['durationMinutes'] as int?) ??
            0,
        author: json['author'] as String?,
        durationMinutes: json['durationMinutes'] as int?,
        coverAsset: json['coverAsset'] as String?,
        coverAltText: json['coverAltText'] as String?,
        file: json['file'] as String?,
      );
}

class ReadingSentence {
  const ReadingSentence({
    required this.index,
    required this.englishText,
    this.turkishText,
  });

  final int index;
  final String englishText;
  final String? turkishText;

  factory ReadingSentence.fromJson(Map<String, Object?> json) =>
      ReadingSentence(
        index: json['index']! as int,
        englishText: json['englishText']! as String,
        turkishText: json['turkishText'] as String?,
      );
}

class ReadingQuestion {
  const ReadingQuestion({
    required this.id,
    required this.sortOrder,
    required this.question,
    required this.options,
    required this.correctOptionIndex,
    this.type,
    this.questionCategory,
    this.questionTr,
    this.optionsTr = const <String>[],
    this.answerEn,
    this.answerTr,
    this.explanation,
    this.explanationTr,
    this.evidenceSentenceIndexes = const <int>[],
  });

  final String id;
  final int sortOrder;
  final String question;
  final List<String> options;
  final int correctOptionIndex;
  final String? type;
  final String? questionCategory;
  final String? questionTr;
  final List<String> optionsTr;
  final String? answerEn;
  final String? answerTr;
  final String? explanation;
  final String? explanationTr;
  final List<int> evidenceSentenceIndexes;

  factory ReadingQuestion.fromJson(Map<String, Object?> json) =>
      ReadingQuestion(
        id: json['id']! as String,
        sortOrder: json['sortOrder']! as int,
        question: json['question']! as String,
        options: _stringList(json['options']),
        correctOptionIndex: json['correctOptionIndex']! as int,
        type: json['type'] as String?,
        questionCategory: json['questionCategory'] as String?,
        questionTr: json['questionTr'] as String?,
        optionsTr: _stringList(json['optionsTr']),
        answerEn: json['answerEn'] as String?,
        answerTr: json['answerTr'] as String?,
        explanation: json['explanation'] as String?,
        explanationTr: json['explanationTr'] as String?,
        evidenceSentenceIndexes: _intList(json['evidenceSentenceIndexes']),
      );
}

class ReadingDetail {
  const ReadingDetail({
    required this.passage,
    required this.sentences,
    required this.focusWordIds,
    required this.questions,
  });

  final ReadingPassage passage;
  final List<ReadingSentence> sentences;
  final List<String> focusWordIds;
  final List<ReadingQuestion> questions;

  factory ReadingDetail.fromJson(Map<String, Object?> json) {
    final sentences =
        ((json['sentences'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => ReadingSentence.fromJson(_jsonMap(item)))
            .toList(growable: false);
    final enrichment = json['enrichment'] is Map
        ? _jsonMap(json['enrichment'])
        : const <String, Object?>{};
    return ReadingDetail(
      passage: ReadingPassage.fromJson(<String, Object?>{
        ...json,
        ...enrichment,
        'sentenceCount': sentences.length,
      }),
      sentences: sentences,
      focusWordIds:
          _stringList(enrichment['focusWordIds'] ?? json['focusWordIds']),
      questions:
          (((enrichment['questions'] ?? json['questions']) as List<Object?>?) ??
                  const <Object?>[])
              .map((item) => ReadingQuestion.fromJson(_jsonMap(item)))
              .toList(growable: false),
    );
  }
}

Map<String, Object?> _jsonMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);

List<String> _stringList(Object? value) =>
    ((value as List<Object?>?) ?? const <Object?>[])
        .whereType<String>()
        .toList(growable: false);

List<int> _intList(Object? value) =>
    ((value as List<Object?>?) ?? const <Object?>[])
        .whereType<int>()
        .toList(growable: false);
