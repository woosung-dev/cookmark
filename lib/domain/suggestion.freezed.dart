// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'suggestion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MissingIngredient {

 String get name;/// 대체재로 해소되면 그 이름 — "우유"가 부족한데 "두유"가 있으면 여기 "두유".
@JsonKey(includeIfNull: false) String? get substitute;
/// Create a copy of MissingIngredient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MissingIngredientCopyWith<MissingIngredient> get copyWith => _$MissingIngredientCopyWithImpl<MissingIngredient>(this as MissingIngredient, _$identity);

  /// Serializes this MissingIngredient to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MissingIngredient&&(identical(other.name, name) || other.name == name)&&(identical(other.substitute, substitute) || other.substitute == substitute));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,substitute);

@override
String toString() {
  return 'MissingIngredient(name: $name, substitute: $substitute)';
}


}

/// @nodoc
abstract mixin class $MissingIngredientCopyWith<$Res>  {
  factory $MissingIngredientCopyWith(MissingIngredient value, $Res Function(MissingIngredient) _then) = _$MissingIngredientCopyWithImpl;
@useResult
$Res call({
 String name,@JsonKey(includeIfNull: false) String? substitute
});




}
/// @nodoc
class _$MissingIngredientCopyWithImpl<$Res>
    implements $MissingIngredientCopyWith<$Res> {
  _$MissingIngredientCopyWithImpl(this._self, this._then);

  final MissingIngredient _self;
  final $Res Function(MissingIngredient) _then;

/// Create a copy of MissingIngredient
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? substitute = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,substitute: freezed == substitute ? _self.substitute : substitute // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MissingIngredient].
extension MissingIngredientPatterns on MissingIngredient {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MissingIngredient value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MissingIngredient() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MissingIngredient value)  $default,){
final _that = this;
switch (_that) {
case _MissingIngredient():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MissingIngredient value)?  $default,){
final _that = this;
switch (_that) {
case _MissingIngredient() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name, @JsonKey(includeIfNull: false)  String? substitute)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MissingIngredient() when $default != null:
return $default(_that.name,_that.substitute);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name, @JsonKey(includeIfNull: false)  String? substitute)  $default,) {final _that = this;
switch (_that) {
case _MissingIngredient():
return $default(_that.name,_that.substitute);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name, @JsonKey(includeIfNull: false)  String? substitute)?  $default,) {final _that = this;
switch (_that) {
case _MissingIngredient() when $default != null:
return $default(_that.name,_that.substitute);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MissingIngredient extends MissingIngredient {
  const _MissingIngredient({required this.name, @JsonKey(includeIfNull: false) this.substitute}): super._();
  factory _MissingIngredient.fromJson(Map<String, dynamic> json) => _$MissingIngredientFromJson(json);

@override final  String name;
/// 대체재로 해소되면 그 이름 — "우유"가 부족한데 "두유"가 있으면 여기 "두유".
@override@JsonKey(includeIfNull: false) final  String? substitute;

/// Create a copy of MissingIngredient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MissingIngredientCopyWith<_MissingIngredient> get copyWith => __$MissingIngredientCopyWithImpl<_MissingIngredient>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MissingIngredientToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MissingIngredient&&(identical(other.name, name) || other.name == name)&&(identical(other.substitute, substitute) || other.substitute == substitute));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,substitute);

@override
String toString() {
  return 'MissingIngredient(name: $name, substitute: $substitute)';
}


}

/// @nodoc
abstract mixin class _$MissingIngredientCopyWith<$Res> implements $MissingIngredientCopyWith<$Res> {
  factory _$MissingIngredientCopyWith(_MissingIngredient value, $Res Function(_MissingIngredient) _then) = __$MissingIngredientCopyWithImpl;
@override @useResult
$Res call({
 String name,@JsonKey(includeIfNull: false) String? substitute
});




}
/// @nodoc
class __$MissingIngredientCopyWithImpl<$Res>
    implements _$MissingIngredientCopyWith<$Res> {
  __$MissingIngredientCopyWithImpl(this._self, this._then);

  final _MissingIngredient _self;
  final $Res Function(_MissingIngredient) _then;

/// Create a copy of MissingIngredient
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? substitute = freezed,}) {
  return _then(_MissingIngredient(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,substitute: freezed == substitute ? _self.substitute : substitute // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$Suggestion {

 String get menu; SuggestionSource get source; List<MissingIngredient> get missing;/// 근거 1줄.
 String get reason;/// 저장 레시피에서 온 제안만 원본 URL을 가진다 — "레시피 보기"가 이걸 새 탭으로 연다.
@JsonKey(includeIfNull: false) String? get recipeUrl;
/// Create a copy of Suggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SuggestionCopyWith<Suggestion> get copyWith => _$SuggestionCopyWithImpl<Suggestion>(this as Suggestion, _$identity);

  /// Serializes this Suggestion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Suggestion&&(identical(other.menu, menu) || other.menu == menu)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.missing, missing)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.recipeUrl, recipeUrl) || other.recipeUrl == recipeUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,menu,source,const DeepCollectionEquality().hash(missing),reason,recipeUrl);

@override
String toString() {
  return 'Suggestion(menu: $menu, source: $source, missing: $missing, reason: $reason, recipeUrl: $recipeUrl)';
}


}

/// @nodoc
abstract mixin class $SuggestionCopyWith<$Res>  {
  factory $SuggestionCopyWith(Suggestion value, $Res Function(Suggestion) _then) = _$SuggestionCopyWithImpl;
@useResult
$Res call({
 String menu, SuggestionSource source, List<MissingIngredient> missing, String reason,@JsonKey(includeIfNull: false) String? recipeUrl
});




}
/// @nodoc
class _$SuggestionCopyWithImpl<$Res>
    implements $SuggestionCopyWith<$Res> {
  _$SuggestionCopyWithImpl(this._self, this._then);

  final Suggestion _self;
  final $Res Function(Suggestion) _then;

/// Create a copy of Suggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? menu = null,Object? source = null,Object? missing = null,Object? reason = null,Object? recipeUrl = freezed,}) {
  return _then(_self.copyWith(
menu: null == menu ? _self.menu : menu // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SuggestionSource,missing: null == missing ? _self.missing : missing // ignore: cast_nullable_to_non_nullable
as List<MissingIngredient>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,recipeUrl: freezed == recipeUrl ? _self.recipeUrl : recipeUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Suggestion].
extension SuggestionPatterns on Suggestion {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Suggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Suggestion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Suggestion value)  $default,){
final _that = this;
switch (_that) {
case _Suggestion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Suggestion value)?  $default,){
final _that = this;
switch (_that) {
case _Suggestion() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String menu,  SuggestionSource source,  List<MissingIngredient> missing,  String reason, @JsonKey(includeIfNull: false)  String? recipeUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Suggestion() when $default != null:
return $default(_that.menu,_that.source,_that.missing,_that.reason,_that.recipeUrl);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String menu,  SuggestionSource source,  List<MissingIngredient> missing,  String reason, @JsonKey(includeIfNull: false)  String? recipeUrl)  $default,) {final _that = this;
switch (_that) {
case _Suggestion():
return $default(_that.menu,_that.source,_that.missing,_that.reason,_that.recipeUrl);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String menu,  SuggestionSource source,  List<MissingIngredient> missing,  String reason, @JsonKey(includeIfNull: false)  String? recipeUrl)?  $default,) {final _that = this;
switch (_that) {
case _Suggestion() when $default != null:
return $default(_that.menu,_that.source,_that.missing,_that.reason,_that.recipeUrl);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Suggestion extends Suggestion {
  const _Suggestion({required this.menu, required this.source, required final  List<MissingIngredient> missing, required this.reason, @JsonKey(includeIfNull: false) this.recipeUrl}): _missing = missing,super._();
  factory _Suggestion.fromJson(Map<String, dynamic> json) => _$SuggestionFromJson(json);

@override final  String menu;
@override final  SuggestionSource source;
 final  List<MissingIngredient> _missing;
@override List<MissingIngredient> get missing {
  if (_missing is EqualUnmodifiableListView) return _missing;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_missing);
}

/// 근거 1줄.
@override final  String reason;
/// 저장 레시피에서 온 제안만 원본 URL을 가진다 — "레시피 보기"가 이걸 새 탭으로 연다.
@override@JsonKey(includeIfNull: false) final  String? recipeUrl;

/// Create a copy of Suggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SuggestionCopyWith<_Suggestion> get copyWith => __$SuggestionCopyWithImpl<_Suggestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SuggestionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Suggestion&&(identical(other.menu, menu) || other.menu == menu)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other._missing, _missing)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.recipeUrl, recipeUrl) || other.recipeUrl == recipeUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,menu,source,const DeepCollectionEquality().hash(_missing),reason,recipeUrl);

@override
String toString() {
  return 'Suggestion(menu: $menu, source: $source, missing: $missing, reason: $reason, recipeUrl: $recipeUrl)';
}


}

/// @nodoc
abstract mixin class _$SuggestionCopyWith<$Res> implements $SuggestionCopyWith<$Res> {
  factory _$SuggestionCopyWith(_Suggestion value, $Res Function(_Suggestion) _then) = __$SuggestionCopyWithImpl;
@override @useResult
$Res call({
 String menu, SuggestionSource source, List<MissingIngredient> missing, String reason,@JsonKey(includeIfNull: false) String? recipeUrl
});




}
/// @nodoc
class __$SuggestionCopyWithImpl<$Res>
    implements _$SuggestionCopyWith<$Res> {
  __$SuggestionCopyWithImpl(this._self, this._then);

  final _Suggestion _self;
  final $Res Function(_Suggestion) _then;

/// Create a copy of Suggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? menu = null,Object? source = null,Object? missing = null,Object? reason = null,Object? recipeUrl = freezed,}) {
  return _then(_Suggestion(
menu: null == menu ? _self.menu : menu // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SuggestionSource,missing: null == missing ? _self._missing : missing // ignore: cast_nullable_to_non_nullable
as List<MissingIngredient>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,recipeUrl: freezed == recipeUrl ? _self.recipeUrl : recipeUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$SuggestionSelection {

 List<Suggestion> get shown;/// 부족 4개 이상이라 제외된 메뉴 수 — 투명성 줄이 이걸 말한다.
 int get excludedCount;
/// Create a copy of SuggestionSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SuggestionSelectionCopyWith<SuggestionSelection> get copyWith => _$SuggestionSelectionCopyWithImpl<SuggestionSelection>(this as SuggestionSelection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SuggestionSelection&&const DeepCollectionEquality().equals(other.shown, shown)&&(identical(other.excludedCount, excludedCount) || other.excludedCount == excludedCount));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(shown),excludedCount);

@override
String toString() {
  return 'SuggestionSelection(shown: $shown, excludedCount: $excludedCount)';
}


}

/// @nodoc
abstract mixin class $SuggestionSelectionCopyWith<$Res>  {
  factory $SuggestionSelectionCopyWith(SuggestionSelection value, $Res Function(SuggestionSelection) _then) = _$SuggestionSelectionCopyWithImpl;
@useResult
$Res call({
 List<Suggestion> shown, int excludedCount
});




}
/// @nodoc
class _$SuggestionSelectionCopyWithImpl<$Res>
    implements $SuggestionSelectionCopyWith<$Res> {
  _$SuggestionSelectionCopyWithImpl(this._self, this._then);

  final SuggestionSelection _self;
  final $Res Function(SuggestionSelection) _then;

/// Create a copy of SuggestionSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shown = null,Object? excludedCount = null,}) {
  return _then(_self.copyWith(
shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as List<Suggestion>,excludedCount: null == excludedCount ? _self.excludedCount : excludedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SuggestionSelection].
extension SuggestionSelectionPatterns on SuggestionSelection {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SuggestionSelection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SuggestionSelection() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SuggestionSelection value)  $default,){
final _that = this;
switch (_that) {
case _SuggestionSelection():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SuggestionSelection value)?  $default,){
final _that = this;
switch (_that) {
case _SuggestionSelection() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Suggestion> shown,  int excludedCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SuggestionSelection() when $default != null:
return $default(_that.shown,_that.excludedCount);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Suggestion> shown,  int excludedCount)  $default,) {final _that = this;
switch (_that) {
case _SuggestionSelection():
return $default(_that.shown,_that.excludedCount);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Suggestion> shown,  int excludedCount)?  $default,) {final _that = this;
switch (_that) {
case _SuggestionSelection() when $default != null:
return $default(_that.shown,_that.excludedCount);case _:
  return null;

}
}

}

/// @nodoc


class _SuggestionSelection implements SuggestionSelection {
  const _SuggestionSelection({required final  List<Suggestion> shown, required this.excludedCount}): _shown = shown;
  

 final  List<Suggestion> _shown;
@override List<Suggestion> get shown {
  if (_shown is EqualUnmodifiableListView) return _shown;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_shown);
}

/// 부족 4개 이상이라 제외된 메뉴 수 — 투명성 줄이 이걸 말한다.
@override final  int excludedCount;

/// Create a copy of SuggestionSelection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SuggestionSelectionCopyWith<_SuggestionSelection> get copyWith => __$SuggestionSelectionCopyWithImpl<_SuggestionSelection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SuggestionSelection&&const DeepCollectionEquality().equals(other._shown, _shown)&&(identical(other.excludedCount, excludedCount) || other.excludedCount == excludedCount));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_shown),excludedCount);

@override
String toString() {
  return 'SuggestionSelection(shown: $shown, excludedCount: $excludedCount)';
}


}

/// @nodoc
abstract mixin class _$SuggestionSelectionCopyWith<$Res> implements $SuggestionSelectionCopyWith<$Res> {
  factory _$SuggestionSelectionCopyWith(_SuggestionSelection value, $Res Function(_SuggestionSelection) _then) = __$SuggestionSelectionCopyWithImpl;
@override @useResult
$Res call({
 List<Suggestion> shown, int excludedCount
});




}
/// @nodoc
class __$SuggestionSelectionCopyWithImpl<$Res>
    implements _$SuggestionSelectionCopyWith<$Res> {
  __$SuggestionSelectionCopyWithImpl(this._self, this._then);

  final _SuggestionSelection _self;
  final $Res Function(_SuggestionSelection) _then;

/// Create a copy of SuggestionSelection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shown = null,Object? excludedCount = null,}) {
  return _then(_SuggestionSelection(
shown: null == shown ? _self._shown : shown // ignore: cast_nullable_to_non_nullable
as List<Suggestion>,excludedCount: null == excludedCount ? _self.excludedCount : excludedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
