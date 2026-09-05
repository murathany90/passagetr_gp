class StudyModuleSummary {
  const StudyModuleSummary({
    required this.id,
    required this.number,
    required this.mainTopic,
    required this.subtopic,
    required this.grammarFocus,
    required this.levelProfile,
    required this.status,
    required this.file,
    required this.counts,
  });

  final String id;
  final int number;
  final String mainTopic;
  final String subtopic;
  final String grammarFocus;
  final String levelProfile;
  final String status;
  final String file;
  final StudyModuleCounts counts;

  factory StudyModuleSummary.fromJson(Map<String, Object?> json) =>
      StudyModuleSummary(
        id: _text(json['module_id']),
        number: int.tryParse(_text(json['module_no'])) ?? 0,
        mainTopic: _text(json['main_topic']),
        subtopic: _text(json['subtopic']),
        grammarFocus: _text(json['grammar_focus']),
        levelProfile: _text(json['level_profile']),
        status: _text(json['status']),
        file: _text(json['file']),
        counts: StudyModuleCounts.fromJson(_map(json['counts'])),
      );
}

class StudyModuleCounts {
  const StudyModuleCounts({
    required this.words,
    required this.sentences,
    required this.readings,
    required this.translations,
    required this.testQuestions,
  });

  final int words;
  final int sentences;
  final int readings;
  final int translations;
  final int testQuestions;

  factory StudyModuleCounts.fromJson(Map<String, Object?> json) =>
      StudyModuleCounts(
        words: _int(json['words']),
        sentences: _int(json['sentences']),
        readings: _int(json['readings']),
        translations: _int(json['translations']),
        testQuestions: _int(json['testQuestions']),
      );
}

class StudyModuleDetail {
  const StudyModuleDetail({
    required this.module,
    required this.words,
    required this.sentences,
    required this.reading,
    required this.translations,
    required this.structures,
    required this.testQuestions,
    required this.review,
  });

  final StudyModuleSummary module;
  final List<StudyWord> words;
  final List<StudySentence> sentences;
  final StudyReading reading;
  final StudyTranslations translations;
  final List<StudyStructure> structures;
  final List<StudyQuestion> testQuestions;
  final List<StudyReviewItem> review;

  factory StudyModuleDetail.fromJson(Map<String, Object?> json) =>
      StudyModuleDetail(
        module: StudyModuleSummary.fromJson(_map(json['module'])),
        words: _list(json['words'])
            .map(StudyWord.fromJson)
            .toList(growable: false),
        sentences: _list(json['sentences'])
            .map(StudySentence.fromJson)
            .toList(growable: false),
        reading: StudyReading.fromJson(_map(json['reading'])),
        translations: StudyTranslations.fromJson(_map(json['translations'])),
        structures: _list(json['structures'])
            .map(StudyStructure.fromJson)
            .toList(growable: false),
        testQuestions: _list(json['testQuestions'])
            .map(StudyQuestion.fromJson)
            .toList(growable: false),
        review: _list(json['review'])
            .map(StudyReviewItem.fromJson)
            .toList(growable: false),
      );
}

class StudyWord {
  const StudyWord({
    required this.id,
    required this.order,
    required this.wordRef,
    required this.headword,
    required this.lexicalFamilyKey,
    required this.level,
    required this.pos,
    required this.meaningTr,
    required this.contextMeaning,
    required this.ydsNote,
    required this.exampleEn,
    required this.exampleTr,
    required this.items,
  });

  final String id;
  final int order;
  final String wordRef;
  final String headword;
  final String lexicalFamilyKey;
  final String level;
  final String pos;
  final String meaningTr;
  final String contextMeaning;
  final String ydsNote;
  final String exampleEn;
  final String exampleTr;
  final List<StudyWordItem> items;

  factory StudyWord.fromJson(Map<String, Object?> json) => StudyWord(
        id: _text(json['word_id']),
        order: _int(json['order_no']),
        wordRef: _text(json['word_ref']),
        headword: _text(json['headword']),
        lexicalFamilyKey: _text(json['lexical_family_key']),
        level: _text(json['level']),
        pos: _text(json['pos']),
        meaningTr: _text(json['meaning_tr']),
        contextMeaning: _text(json['context_meaning']),
        ydsNote: _text(json['yds_note']),
        exampleEn: _text(json['example_en']),
        exampleTr: _text(json['example_tr']),
        items: _list(json['items'])
            .map(StudyWordItem.fromJson)
            .toList(growable: false),
      );
}

class StudyWordItem {
  const StudyWordItem({
    required this.type,
    required this.subtype,
    required this.valueEn,
    required this.valueTr,
    required this.usageNote,
  });

  final String type;
  final String subtype;
  final String valueEn;
  final String valueTr;
  final String usageNote;

  factory StudyWordItem.fromJson(Map<String, Object?> json) => StudyWordItem(
        type: _text(json['item_type']),
        subtype: _text(json['item_subtype']),
        valueEn: _text(json['value_en']),
        valueTr: _text(json['value_tr']),
        usageNote: _text(json['usage_note']),
      );
}

class StudySentence {
  const StudySentence({
    required this.order,
    required this.level,
    required this.english,
    required this.turkish,
    required this.analysis,
  });

  final int order;
  final String level;
  final String english;
  final String turkish;
  final Map<String, String> analysis;

  factory StudySentence.fromJson(Map<String, Object?> json) => StudySentence(
        order: _int(json['order_no']),
        level: _text(json['level']),
        english: _text(json['sentence_en']),
        turkish: _text(json['translation_tr']),
        analysis: <String, String>{
          'İskelet': _text(json['skeleton']),
          'Ana özne': _text(json['main_subject']),
          'Çekimli fiil': _text(json['finite_verb']),
          'Nesne / tümleç': _text(json['object_complement']),
          'Yan yapılar': _text(json['side_structures']),
          'Fiil haritası': _text(json['verb_map']),
          'Bağlaç': _text(json['connector']),
          'Öbekler': _text(json['phrase_groups']),
          'Referans kelimeler': _text(json['reference_words']),
          'Gramer analizi': _text(json['grammar_analysis']),
          'YDS notu': _text(json['yds_note']),
          'Çeviri stratejisi': _text(json['translation_strategy']),
        }..removeWhere((_, value) => value.isEmpty),
      );
}

class StudyReading {
  const StudyReading({
    required this.title,
    required this.textEn,
    required this.mainIdeaTr,
    required this.flowAnalysis,
    required this.importantWords,
    required this.connectorMap,
    required this.referenceAnalysis,
    required this.questions,
  });

  final String title;
  final String textEn;
  final String mainIdeaTr;
  final String flowAnalysis;
  final String importantWords;
  final String connectorMap;
  final String referenceAnalysis;
  final List<StudyQuestion> questions;

  factory StudyReading.fromJson(Map<String, Object?> json) => StudyReading(
        title: _text(json['title']),
        textEn: _text(json['text_en']),
        mainIdeaTr: _text(json['main_idea_tr']),
        flowAnalysis: _text(json['flow_analysis']),
        importantWords: _text(json['important_words']),
        connectorMap: _text(json['connector_map']),
        referenceAnalysis: _text(json['reference_analysis']),
        questions: _list(json['questions'])
            .map(StudyQuestion.fromJson)
            .toList(growable: false),
      );
}

class StudyQuestion {
  const StudyQuestion({
    required this.id,
    required this.type,
    required this.order,
    required this.stem,
    required this.correctOption,
    required this.evidence,
    required this.whyCorrect,
    required this.reminderPattern,
    required this.options,
  });

  final String id;
  final String type;
  final int order;
  final String stem;
  final String correctOption;
  final String evidence;
  final String whyCorrect;
  final String reminderPattern;
  final List<StudyQuestionOption> options;

  factory StudyQuestion.fromJson(Map<String, Object?> json) => StudyQuestion(
        id: _text(json['question_id']),
        type: _text(json['question_type']),
        order: _int(json['order_no']),
        stem: _text(json['stem']),
        correctOption: _text(json['correct_option']),
        evidence: _text(json['evidence']),
        whyCorrect: _text(json['why_correct']),
        reminderPattern: _text(json['reminder_pattern']),
        options: _list(json['options'])
            .map(StudyQuestionOption.fromJson)
            .toList(growable: false),
      );
}

class StudyQuestionOption {
  const StudyQuestionOption({
    required this.letter,
    required this.text,
    required this.isCorrect,
    required this.explanation,
  });

  final String letter;
  final String text;
  final bool isCorrect;
  final String explanation;

  factory StudyQuestionOption.fromJson(Map<String, Object?> json) =>
      StudyQuestionOption(
        letter: _text(json['option_letter']),
        text: _text(json['option_text']),
        isCorrect: _truthy(json['is_correct']),
        explanation: _text(json['explanation']),
      );
}

class StudyTranslations {
  const StudyTranslations({required this.enTr, required this.trEn});

  final List<StudyTranslation> enTr;
  final List<StudyTranslation> trEn;

  factory StudyTranslations.fromJson(Map<String, Object?> json) =>
      StudyTranslations(
        enTr: _list(json['enTr'])
            .map(StudyTranslation.fromJson)
            .toList(growable: false),
        trEn: _list(json['trEn'])
            .map(StudyTranslation.fromJson)
            .toList(growable: false),
      );
}

class StudyTranslation {
  const StudyTranslation({
    required this.order,
    required this.source,
    required this.answer,
    required this.alternative,
    required this.skeleton,
    required this.keyWords,
    required this.grammarNote,
    required this.logic,
  });

  final int order;
  final String source;
  final String answer;
  final String alternative;
  final String skeleton;
  final String keyWords;
  final String grammarNote;
  final String logic;

  factory StudyTranslation.fromJson(Map<String, Object?> json) =>
      StudyTranslation(
        order: _int(json['order_no']),
        source: _text(json['source_text']),
        answer: _text(json['primary_translation']),
        alternative: _text(json['alternative_translation']),
        skeleton: _text(json['skeleton_pattern']),
        keyWords: _text(json['key_words']),
        grammarNote: _text(json['grammar_note']),
        logic: _text(json['translation_logic']),
      );
}

class StudyStructure {
  const StudyStructure({
    required this.category,
    required this.order,
    required this.expression,
    required this.meaningTr,
    required this.pattern,
    required this.example,
    required this.confusionNote,
    required this.relatedWords,
    required this.note,
  });

  final String category;
  final int order;
  final String expression;
  final String meaningTr;
  final String pattern;
  final String example;
  final String confusionNote;
  final String relatedWords;
  final String note;

  factory StudyStructure.fromJson(Map<String, Object?> json) => StudyStructure(
        category: _text(json['category']),
        order: _int(json['order_no']),
        expression: _text(json['expression']),
        meaningTr: _text(json['meaning_tr']),
        pattern: _text(json['structure_pattern']),
        example: _text(json['example_en']),
        confusionNote: _text(json['confusion_note']),
        relatedWords: _text(json['related_words']),
        note: _text(json['note']),
      );
}

class StudyReviewItem {
  const StudyReviewItem({
    required this.type,
    required this.order,
    required this.promptEn,
    required this.promptTr,
    required this.answerEn,
    required this.answerTr,
    required this.note,
  });

  final String type;
  final int order;
  final String promptEn;
  final String promptTr;
  final String answerEn;
  final String answerTr;
  final String note;

  factory StudyReviewItem.fromJson(Map<String, Object?> json) =>
      StudyReviewItem(
        type: _text(json['item_type']),
        order: _int(json['order_no']),
        promptEn: _text(json['prompt_en']),
        promptTr: _text(json['prompt_tr']),
        answerEn: _text(json['answer_en']),
        answerTr: _text(json['answer_tr']),
        note: _text(json['note']),
      );
}

List<Map<String, Object?>> _list(Object? value) =>
    ((value as List<Object?>?) ?? const <Object?>[]).map(_map).toList();

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);

String _text(Object? value) => value?.toString() ?? '';

int _int(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

bool _truthy(Object? value) {
  final text = _text(value).toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}
