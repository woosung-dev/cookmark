// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'suggestion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MissingIngredient _$MissingIngredientFromJson(Map<String, dynamic> json) =>
    _MissingIngredient(
      name: json['name'] as String,
      substitute: json['substitute'] as String?,
    );

Map<String, dynamic> _$MissingIngredientToJson(_MissingIngredient instance) =>
    <String, dynamic>{
      'name': instance.name,
      'substitute': ?instance.substitute,
    };

_Suggestion _$SuggestionFromJson(Map<String, dynamic> json) => _Suggestion(
  menu: json['menu'] as String,
  source: $enumDecode(_$SuggestionSourceEnumMap, json['source']),
  missing: (json['missing'] as List<dynamic>)
      .map((e) => MissingIngredient.fromJson(e as Map<String, dynamic>))
      .toList(),
  reason: json['reason'] as String,
  recipeUrl: json['recipeUrl'] as String?,
);

Map<String, dynamic> _$SuggestionToJson(_Suggestion instance) =>
    <String, dynamic>{
      'menu': instance.menu,
      'source': _$SuggestionSourceEnumMap[instance.source]!,
      'missing': instance.missing,
      'reason': instance.reason,
      'recipeUrl': ?instance.recipeUrl,
    };

const _$SuggestionSourceEnumMap = {
  SuggestionSource.saved: 'saved',
  SuggestionSource.generated: 'generated',
};
