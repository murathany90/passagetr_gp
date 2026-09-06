class TestBankManifest {
  const TestBankManifest({
    required this.canonicalSource,
    required this.sourceHash,
    required this.counts,
    required this.modules,
    required this.structuresFile,
    required this.exams,
  });

  final String canonicalSource;
  final String sourceHash;
  final TestBankCounts counts;
  final List<TestModuleSummary> modules;
  final String structuresFile;
  final List<TestExamSummary> exams;

  factory TestBankManifest.fromJson(Map<String, Object?> json) =>
      TestBankManifest(
        canonicalSource: _text(json['canonicalSource']),
        sourceHash: _text(json['sourceHash']),
        counts: TestBankCounts.fromJson(_map(json['counts'])),
        modules: _list(json['modules'])
            .map(TestModuleSummary.fromJson)
            .toList(growable: false),
        structuresFile: _text(json['structuresFile']),
        exams: _list(json['exams'])
            .map(TestExamSummary.fromJson)
            .toList(growable: false),
      );
}

class TestBankCounts {
  const TestBankCounts({
    required this.modules,
    required this.wordRows,
    required this.uniqueHeadwords,
    required this.structures,
    required this.structureCategories,
    required this.exams,
    required this.questions,
    required this.options,
    required this.optionTrCovered,
    required this.optionTrMissing,
  });

  final int modules;
  final int wordRows;
  final int uniqueHeadwords;
  final int structures;
  final int structureCategories;
  final int exams;
  final int questions;
  final int options;
  final int optionTrCovered;
  final int optionTrMissing;

  factory TestBankCounts.fromJson(Map<String, Object?> json) => TestBankCounts(
        modules: _int(json['modules']),
        wordRows: _int(json['wordRows']),
        uniqueHeadwords: _int(json['uniqueHeadwords']),
        structures: _int(json['structures']),
        structureCategories: _int(json['structureCategories']),
        exams: _int(json['exams']),
        questions: _int(json['questions']),
        options: _int(json['options']),
        optionTrCovered: _int(json['optionTrCovered']),
        optionTrMissing: _int(json['optionTrMissing']),
      );
}

class TestModuleSummary {
  const TestModuleSummary({
    required this.id,
    required this.moduleNo,
    required this.wordCount,
    required this.file,
  });

  final String id;
  final int moduleNo;
  final int wordCount;
  final String file;

  factory TestModuleSummary.fromJson(Map<String, Object?> json) =>
      TestModuleSummary(
        id: _text(json['id']),
        moduleNo: _int(json['moduleNo']),
        wordCount: _int(json['wordCount']),
        file: _text(json['file']),
      );
}

class TestModuleDetail {
  const TestModuleDetail({required this.moduleNo, required this.words});

  final int moduleNo;
  final List<TestBankWord> words;

  factory TestModuleDetail.fromJson(Map<String, Object?> json) =>
      TestModuleDetail(
        moduleNo: _int(json['moduleNo']),
        words: _list(json['words'])
            .map(TestBankWord.fromJson)
            .toList(growable: false),
      );
}

class TestBankWord {
  const TestBankWord({
    required this.id,
    required this.order,
    required this.headword,
    required this.meaningTr,
    required this.pos,
    required this.exampleEn,
    required this.exampleTr,
    required this.synonymsRaw,
  });

  final String id;
  final int order;
  final String headword;
  final String meaningTr;
  final String pos;
  final String exampleEn;
  final String exampleTr;
  final String? synonymsRaw;

  factory TestBankWord.fromJson(Map<String, Object?> json) => TestBankWord(
        id: _text(json['id']),
        order: _int(json['order']),
        headword: _text(json['headword']),
        meaningTr: _text(json['meaningTr']),
        pos: _text(json['pos']),
        exampleEn: _text(json['exampleEn']),
        exampleTr: _text(json['exampleTr']),
        synonymsRaw: _nullable(json['synonymsRaw']),
      );
}

class TestStructureBank {
  const TestStructureBank({required this.categories, required this.structures});

  final List<String> categories;
  final List<TestStructure> structures;

  factory TestStructureBank.fromJson(Map<String, Object?> json) =>
      TestStructureBank(
        categories: _stringList(json['categories']),
        structures: _list(json['structures'])
            .map(TestStructure.fromJson)
            .toList(growable: false),
      );
}

class TestStructure {
  const TestStructure({
    required this.id,
    required this.category,
    required this.structure,
    required this.meaningTr,
    required this.exampleEn,
    required this.exampleTr,
  });

  final String id;
  final String category;
  final String structure;
  final String meaningTr;
  final String? exampleEn;
  final String? exampleTr;

  factory TestStructure.fromJson(Map<String, Object?> json) => TestStructure(
        id: _text(json['id']),
        category: _text(json['category']),
        structure: _text(json['structure']),
        meaningTr: _text(json['meaningTr']),
        exampleEn: _nullable(json['exampleEn']),
        exampleTr: _nullable(json['exampleTr']),
      );
}

class TestExamSummary {
  const TestExamSummary({
    required this.testNo,
    required this.questionCount,
    required this.file,
  });

  final int testNo;
  final int questionCount;
  final String file;

  factory TestExamSummary.fromJson(Map<String, Object?> json) =>
      TestExamSummary(
        testNo: _int(json['testNo']),
        questionCount: _int(json['questionCount']),
        file: _text(json['file']),
      );
}

class TestExam {
  const TestExam({required this.testNo, required this.questions});

  final int testNo;
  final List<TestExamQuestion> questions;

  factory TestExam.fromJson(Map<String, Object?> json) => TestExam(
        testNo: _int(json['testNo']),
        questions: _list(json['questions'])
            .map(TestExamQuestion.fromJson)
            .toList(growable: false),
      );
}

class TestExamQuestion {
  const TestExamQuestion({
    required this.id,
    required this.number,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.fingerprint,
  });

  final String id;
  final int number;
  final String question;
  final List<TestExamOption> options;
  final String correctAnswer;
  final String fingerprint;

  factory TestExamQuestion.fromJson(Map<String, Object?> json) =>
      TestExamQuestion(
        id: _text(json['id']),
        number: _int(json['number']),
        question: _text(json['question']),
        options: _list(json['options'])
            .map(TestExamOption.fromJson)
            .toList(growable: false),
        correctAnswer: _text(json['correctAnswer']),
        fingerprint: _text(json['fingerprint']),
      );
}

class TestExamOption {
  const TestExamOption({
    required this.key,
    required this.textEn,
    required this.textTr,
  });

  final String key;
  final String textEn;
  final String? textTr;

  factory TestExamOption.fromJson(Map<String, Object?> json) => TestExamOption(
        key: _text(json['key']),
        textEn: _text(json['textEn']),
        textTr: _nullable(json['textTr']),
      );
}

class TestQuestionContentContract {
  const TestQuestionContentContract({
    required this.version,
    required this.fingerprints,
  });

  final String version;
  final Map<String, String> fingerprints;
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);

List<Map<String, Object?>> _list(Object? value) =>
    ((value as List<Object?>?) ?? const <Object?>[]).map(_map).toList();

List<String> _stringList(Object? value) =>
    ((value as List<Object?>?) ?? const <Object?>[])
        .map(_text)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullable(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

int _int(Object? value) => int.tryParse(_text(value)) ?? 0;
