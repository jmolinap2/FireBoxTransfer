// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'http.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsHttpClientError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsHttpClientError()';
}


}

/// @nodoc
class $RsHttpClientErrorCopyWith<$Res>  {
$RsHttpClientErrorCopyWith(RsHttpClientError _, $Res Function(RsHttpClientError) __);
}


/// Adds pattern-matching-related methods to [RsHttpClientError].
extension RsHttpClientErrorPatterns on RsHttpClientError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsHttpClientError_StatusCode value)?  statusCode,TResult Function( RsHttpClientError_Reqwest value)?  reqwest,TResult Function( RsHttpClientError_Json value)?  json,TResult Function( RsHttpClientError_Io value)?  io,TResult Function( RsHttpClientError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsHttpClientError_StatusCode value)  statusCode,required TResult Function( RsHttpClientError_Reqwest value)  reqwest,required TResult Function( RsHttpClientError_Json value)  json,required TResult Function( RsHttpClientError_Io value)  io,required TResult Function( RsHttpClientError_Other value)  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that);case RsHttpClientError_Reqwest():
return reqwest(_that);case RsHttpClientError_Json():
return json(_that);case RsHttpClientError_Io():
return io(_that);case RsHttpClientError_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsHttpClientError_StatusCode value)?  statusCode,TResult? Function( RsHttpClientError_Reqwest value)?  reqwest,TResult? Function( RsHttpClientError_Json value)?  json,TResult? Function( RsHttpClientError_Io value)?  io,TResult? Function( RsHttpClientError_Other value)?  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int status,  String? message)?  statusCode,TResult Function( String field0)?  reqwest,TResult Function( String field0)?  json,TResult Function( String field0)?  io,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int status,  String? message)  statusCode,required TResult Function( String field0)  reqwest,required TResult Function( String field0)  json,required TResult Function( String field0)  io,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest():
return reqwest(_that.field0);case RsHttpClientError_Json():
return json(_that.field0);case RsHttpClientError_Io():
return io(_that.field0);case RsHttpClientError_Other():
return other(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int status,  String? message)?  statusCode,TResult? Function( String field0)?  reqwest,TResult? Function( String field0)?  json,TResult? Function( String field0)?  io,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RsHttpClientError_StatusCode extends RsHttpClientError {
  const RsHttpClientError_StatusCode({required this.status, this.message}): super._();
  

 final  int status;
 final  String? message;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_StatusCodeCopyWith<RsHttpClientError_StatusCode> get copyWith => _$RsHttpClientError_StatusCodeCopyWithImpl<RsHttpClientError_StatusCode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_StatusCode&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,status,message);

@override
String toString() {
  return 'RsHttpClientError.statusCode(status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_StatusCodeCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_StatusCodeCopyWith(RsHttpClientError_StatusCode value, $Res Function(RsHttpClientError_StatusCode) _then) = _$RsHttpClientError_StatusCodeCopyWithImpl;
@useResult
$Res call({
 int status, String? message
});




}
/// @nodoc
class _$RsHttpClientError_StatusCodeCopyWithImpl<$Res>
    implements $RsHttpClientError_StatusCodeCopyWith<$Res> {
  _$RsHttpClientError_StatusCodeCopyWithImpl(this._self, this._then);

  final RsHttpClientError_StatusCode _self;
  final $Res Function(RsHttpClientError_StatusCode) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = freezed,}) {
  return _then(RsHttpClientError_StatusCode(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsHttpClientError_Reqwest extends RsHttpClientError {
  const RsHttpClientError_Reqwest(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_ReqwestCopyWith<RsHttpClientError_Reqwest> get copyWith => _$RsHttpClientError_ReqwestCopyWithImpl<RsHttpClientError_Reqwest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Reqwest&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.reqwest(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_ReqwestCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_ReqwestCopyWith(RsHttpClientError_Reqwest value, $Res Function(RsHttpClientError_Reqwest) _then) = _$RsHttpClientError_ReqwestCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_ReqwestCopyWithImpl<$Res>
    implements $RsHttpClientError_ReqwestCopyWith<$Res> {
  _$RsHttpClientError_ReqwestCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Reqwest _self;
  final $Res Function(RsHttpClientError_Reqwest) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Reqwest(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Json extends RsHttpClientError {
  const RsHttpClientError_Json(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_JsonCopyWith<RsHttpClientError_Json> get copyWith => _$RsHttpClientError_JsonCopyWithImpl<RsHttpClientError_Json>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Json&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.json(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_JsonCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_JsonCopyWith(RsHttpClientError_Json value, $Res Function(RsHttpClientError_Json) _then) = _$RsHttpClientError_JsonCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_JsonCopyWithImpl<$Res>
    implements $RsHttpClientError_JsonCopyWith<$Res> {
  _$RsHttpClientError_JsonCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Json _self;
  final $Res Function(RsHttpClientError_Json) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Json(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Io extends RsHttpClientError {
  const RsHttpClientError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_IoCopyWith<RsHttpClientError_Io> get copyWith => _$RsHttpClientError_IoCopyWithImpl<RsHttpClientError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_IoCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_IoCopyWith(RsHttpClientError_Io value, $Res Function(RsHttpClientError_Io) _then) = _$RsHttpClientError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_IoCopyWithImpl<$Res>
    implements $RsHttpClientError_IoCopyWith<$Res> {
  _$RsHttpClientError_IoCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Io _self;
  final $Res Function(RsHttpClientError_Io) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Other extends RsHttpClientError {
  const RsHttpClientError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_OtherCopyWith<RsHttpClientError_Other> get copyWith => _$RsHttpClientError_OtherCopyWithImpl<RsHttpClientError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_OtherCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_OtherCopyWith(RsHttpClientError_Other value, $Res Function(RsHttpClientError_Other) _then) = _$RsHttpClientError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_OtherCopyWithImpl<$Res>
    implements $RsHttpClientError_OtherCopyWith<$Res> {
  _$RsHttpClientError_OtherCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Other _self;
  final $Res Function(RsHttpClientError_Other) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsRemoteFsClientError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRemoteFsClientError()';
}


}

/// @nodoc
class $RsRemoteFsClientErrorCopyWith<$Res>  {
$RsRemoteFsClientErrorCopyWith(RsRemoteFsClientError _, $Res Function(RsRemoteFsClientError) __);
}


/// Adds pattern-matching-related methods to [RsRemoteFsClientError].
extension RsRemoteFsClientErrorPatterns on RsRemoteFsClientError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRemoteFsClientError_Remote value)?  remote,TResult Function( RsRemoteFsClientError_Setup value)?  setup,TResult Function( RsRemoteFsClientError_Reqwest value)?  reqwest,TResult Function( RsRemoteFsClientError_Json value)?  json,TResult Function( RsRemoteFsClientError_Io value)?  io,TResult Function( RsRemoteFsClientError_InvalidRequest value)?  invalidRequest,TResult Function( RsRemoteFsClientError_InvalidResponse value)?  invalidResponse,TResult Function( RsRemoteFsClientError_Cancelled value)?  cancelled,TResult Function( RsRemoteFsClientError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote() when remote != null:
return remote(_that);case RsRemoteFsClientError_Setup() when setup != null:
return setup(_that);case RsRemoteFsClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsRemoteFsClientError_Json() when json != null:
return json(_that);case RsRemoteFsClientError_Io() when io != null:
return io(_that);case RsRemoteFsClientError_InvalidRequest() when invalidRequest != null:
return invalidRequest(_that);case RsRemoteFsClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that);case RsRemoteFsClientError_Cancelled() when cancelled != null:
return cancelled(_that);case RsRemoteFsClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRemoteFsClientError_Remote value)  remote,required TResult Function( RsRemoteFsClientError_Setup value)  setup,required TResult Function( RsRemoteFsClientError_Reqwest value)  reqwest,required TResult Function( RsRemoteFsClientError_Json value)  json,required TResult Function( RsRemoteFsClientError_Io value)  io,required TResult Function( RsRemoteFsClientError_InvalidRequest value)  invalidRequest,required TResult Function( RsRemoteFsClientError_InvalidResponse value)  invalidResponse,required TResult Function( RsRemoteFsClientError_Cancelled value)  cancelled,required TResult Function( RsRemoteFsClientError_Other value)  other,}){
final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote():
return remote(_that);case RsRemoteFsClientError_Setup():
return setup(_that);case RsRemoteFsClientError_Reqwest():
return reqwest(_that);case RsRemoteFsClientError_Json():
return json(_that);case RsRemoteFsClientError_Io():
return io(_that);case RsRemoteFsClientError_InvalidRequest():
return invalidRequest(_that);case RsRemoteFsClientError_InvalidResponse():
return invalidResponse(_that);case RsRemoteFsClientError_Cancelled():
return cancelled(_that);case RsRemoteFsClientError_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRemoteFsClientError_Remote value)?  remote,TResult? Function( RsRemoteFsClientError_Setup value)?  setup,TResult? Function( RsRemoteFsClientError_Reqwest value)?  reqwest,TResult? Function( RsRemoteFsClientError_Json value)?  json,TResult? Function( RsRemoteFsClientError_Io value)?  io,TResult? Function( RsRemoteFsClientError_InvalidRequest value)?  invalidRequest,TResult? Function( RsRemoteFsClientError_InvalidResponse value)?  invalidResponse,TResult? Function( RsRemoteFsClientError_Cancelled value)?  cancelled,TResult? Function( RsRemoteFsClientError_Other value)?  other,}){
final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote() when remote != null:
return remote(_that);case RsRemoteFsClientError_Setup() when setup != null:
return setup(_that);case RsRemoteFsClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsRemoteFsClientError_Json() when json != null:
return json(_that);case RsRemoteFsClientError_Io() when io != null:
return io(_that);case RsRemoteFsClientError_InvalidRequest() when invalidRequest != null:
return invalidRequest(_that);case RsRemoteFsClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that);case RsRemoteFsClientError_Cancelled() when cancelled != null:
return cancelled(_that);case RsRemoteFsClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int status,  RemoteFsErrorCode code,  String message)?  remote,TResult Function( String field0)?  setup,TResult Function( String field0)?  reqwest,TResult Function( String field0)?  json,TResult Function( String field0)?  io,TResult Function( RemoteFsErrorCode code)?  invalidRequest,TResult Function()?  invalidResponse,TResult Function()?  cancelled,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote() when remote != null:
return remote(_that.status,_that.code,_that.message);case RsRemoteFsClientError_Setup() when setup != null:
return setup(_that.field0);case RsRemoteFsClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsRemoteFsClientError_Json() when json != null:
return json(_that.field0);case RsRemoteFsClientError_Io() when io != null:
return io(_that.field0);case RsRemoteFsClientError_InvalidRequest() when invalidRequest != null:
return invalidRequest(_that.code);case RsRemoteFsClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse();case RsRemoteFsClientError_Cancelled() when cancelled != null:
return cancelled();case RsRemoteFsClientError_Other() when other != null:
return other(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int status,  RemoteFsErrorCode code,  String message)  remote,required TResult Function( String field0)  setup,required TResult Function( String field0)  reqwest,required TResult Function( String field0)  json,required TResult Function( String field0)  io,required TResult Function( RemoteFsErrorCode code)  invalidRequest,required TResult Function()  invalidResponse,required TResult Function()  cancelled,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote():
return remote(_that.status,_that.code,_that.message);case RsRemoteFsClientError_Setup():
return setup(_that.field0);case RsRemoteFsClientError_Reqwest():
return reqwest(_that.field0);case RsRemoteFsClientError_Json():
return json(_that.field0);case RsRemoteFsClientError_Io():
return io(_that.field0);case RsRemoteFsClientError_InvalidRequest():
return invalidRequest(_that.code);case RsRemoteFsClientError_InvalidResponse():
return invalidResponse();case RsRemoteFsClientError_Cancelled():
return cancelled();case RsRemoteFsClientError_Other():
return other(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int status,  RemoteFsErrorCode code,  String message)?  remote,TResult? Function( String field0)?  setup,TResult? Function( String field0)?  reqwest,TResult? Function( String field0)?  json,TResult? Function( String field0)?  io,TResult? Function( RemoteFsErrorCode code)?  invalidRequest,TResult? Function()?  invalidResponse,TResult? Function()?  cancelled,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case RsRemoteFsClientError_Remote() when remote != null:
return remote(_that.status,_that.code,_that.message);case RsRemoteFsClientError_Setup() when setup != null:
return setup(_that.field0);case RsRemoteFsClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsRemoteFsClientError_Json() when json != null:
return json(_that.field0);case RsRemoteFsClientError_Io() when io != null:
return io(_that.field0);case RsRemoteFsClientError_InvalidRequest() when invalidRequest != null:
return invalidRequest(_that.code);case RsRemoteFsClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse();case RsRemoteFsClientError_Cancelled() when cancelled != null:
return cancelled();case RsRemoteFsClientError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RsRemoteFsClientError_Remote extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Remote({required this.status, required this.code, required this.message}): super._();
  

 final  int status;
 final  RemoteFsErrorCode code;
 final  String message;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_RemoteCopyWith<RsRemoteFsClientError_Remote> get copyWith => _$RsRemoteFsClientError_RemoteCopyWithImpl<RsRemoteFsClientError_Remote>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Remote&&(identical(other.status, status) || other.status == status)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,status,code,message);

@override
String toString() {
  return 'RsRemoteFsClientError.remote(status: $status, code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_RemoteCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_RemoteCopyWith(RsRemoteFsClientError_Remote value, $Res Function(RsRemoteFsClientError_Remote) _then) = _$RsRemoteFsClientError_RemoteCopyWithImpl;
@useResult
$Res call({
 int status, RemoteFsErrorCode code, String message
});




}
/// @nodoc
class _$RsRemoteFsClientError_RemoteCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_RemoteCopyWith<$Res> {
  _$RsRemoteFsClientError_RemoteCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Remote _self;
  final $Res Function(RsRemoteFsClientError_Remote) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? code = null,Object? message = null,}) {
  return _then(RsRemoteFsClientError_Remote(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as RemoteFsErrorCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_Setup extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Setup(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_SetupCopyWith<RsRemoteFsClientError_Setup> get copyWith => _$RsRemoteFsClientError_SetupCopyWithImpl<RsRemoteFsClientError_Setup>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Setup&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsRemoteFsClientError.setup(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_SetupCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_SetupCopyWith(RsRemoteFsClientError_Setup value, $Res Function(RsRemoteFsClientError_Setup) _then) = _$RsRemoteFsClientError_SetupCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsRemoteFsClientError_SetupCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_SetupCopyWith<$Res> {
  _$RsRemoteFsClientError_SetupCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Setup _self;
  final $Res Function(RsRemoteFsClientError_Setup) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsRemoteFsClientError_Setup(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_Reqwest extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Reqwest(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_ReqwestCopyWith<RsRemoteFsClientError_Reqwest> get copyWith => _$RsRemoteFsClientError_ReqwestCopyWithImpl<RsRemoteFsClientError_Reqwest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Reqwest&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsRemoteFsClientError.reqwest(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_ReqwestCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_ReqwestCopyWith(RsRemoteFsClientError_Reqwest value, $Res Function(RsRemoteFsClientError_Reqwest) _then) = _$RsRemoteFsClientError_ReqwestCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsRemoteFsClientError_ReqwestCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_ReqwestCopyWith<$Res> {
  _$RsRemoteFsClientError_ReqwestCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Reqwest _self;
  final $Res Function(RsRemoteFsClientError_Reqwest) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsRemoteFsClientError_Reqwest(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_Json extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Json(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_JsonCopyWith<RsRemoteFsClientError_Json> get copyWith => _$RsRemoteFsClientError_JsonCopyWithImpl<RsRemoteFsClientError_Json>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Json&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsRemoteFsClientError.json(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_JsonCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_JsonCopyWith(RsRemoteFsClientError_Json value, $Res Function(RsRemoteFsClientError_Json) _then) = _$RsRemoteFsClientError_JsonCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsRemoteFsClientError_JsonCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_JsonCopyWith<$Res> {
  _$RsRemoteFsClientError_JsonCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Json _self;
  final $Res Function(RsRemoteFsClientError_Json) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsRemoteFsClientError_Json(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_Io extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_IoCopyWith<RsRemoteFsClientError_Io> get copyWith => _$RsRemoteFsClientError_IoCopyWithImpl<RsRemoteFsClientError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsRemoteFsClientError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_IoCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_IoCopyWith(RsRemoteFsClientError_Io value, $Res Function(RsRemoteFsClientError_Io) _then) = _$RsRemoteFsClientError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsRemoteFsClientError_IoCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_IoCopyWith<$Res> {
  _$RsRemoteFsClientError_IoCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Io _self;
  final $Res Function(RsRemoteFsClientError_Io) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsRemoteFsClientError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_InvalidRequest extends RsRemoteFsClientError {
  const RsRemoteFsClientError_InvalidRequest({required this.code}): super._();
  

 final  RemoteFsErrorCode code;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_InvalidRequestCopyWith<RsRemoteFsClientError_InvalidRequest> get copyWith => _$RsRemoteFsClientError_InvalidRequestCopyWithImpl<RsRemoteFsClientError_InvalidRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_InvalidRequest&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,code);

@override
String toString() {
  return 'RsRemoteFsClientError.invalidRequest(code: $code)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_InvalidRequestCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_InvalidRequestCopyWith(RsRemoteFsClientError_InvalidRequest value, $Res Function(RsRemoteFsClientError_InvalidRequest) _then) = _$RsRemoteFsClientError_InvalidRequestCopyWithImpl;
@useResult
$Res call({
 RemoteFsErrorCode code
});




}
/// @nodoc
class _$RsRemoteFsClientError_InvalidRequestCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_InvalidRequestCopyWith<$Res> {
  _$RsRemoteFsClientError_InvalidRequestCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_InvalidRequest _self;
  final $Res Function(RsRemoteFsClientError_InvalidRequest) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(RsRemoteFsClientError_InvalidRequest(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as RemoteFsErrorCode,
  ));
}


}

/// @nodoc


class RsRemoteFsClientError_InvalidResponse extends RsRemoteFsClientError {
  const RsRemoteFsClientError_InvalidResponse(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_InvalidResponse);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRemoteFsClientError.invalidResponse()';
}


}




/// @nodoc


class RsRemoteFsClientError_Cancelled extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRemoteFsClientError.cancelled()';
}


}




/// @nodoc


class RsRemoteFsClientError_Other extends RsRemoteFsClientError {
  const RsRemoteFsClientError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsClientError_OtherCopyWith<RsRemoteFsClientError_Other> get copyWith => _$RsRemoteFsClientError_OtherCopyWithImpl<RsRemoteFsClientError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsClientError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsRemoteFsClientError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsClientError_OtherCopyWith<$Res> implements $RsRemoteFsClientErrorCopyWith<$Res> {
  factory $RsRemoteFsClientError_OtherCopyWith(RsRemoteFsClientError_Other value, $Res Function(RsRemoteFsClientError_Other) _then) = _$RsRemoteFsClientError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsRemoteFsClientError_OtherCopyWithImpl<$Res>
    implements $RsRemoteFsClientError_OtherCopyWith<$Res> {
  _$RsRemoteFsClientError_OtherCopyWithImpl(this._self, this._then);

  final RsRemoteFsClientError_Other _self;
  final $Res Function(RsRemoteFsClientError_Other) _then;

/// Create a copy of RsRemoteFsClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsRemoteFsClientError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsRemoteFsWriteEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsWriteEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRemoteFsWriteEvent()';
}


}

/// @nodoc
class $RsRemoteFsWriteEventCopyWith<$Res>  {
$RsRemoteFsWriteEventCopyWith(RsRemoteFsWriteEvent _, $Res Function(RsRemoteFsWriteEvent) __);
}


/// Adds pattern-matching-related methods to [RsRemoteFsWriteEvent].
extension RsRemoteFsWriteEventPatterns on RsRemoteFsWriteEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRemoteFsWriteEvent_Progress value)?  progress,TResult Function( RsRemoteFsWriteEvent_Completed value)?  completed,TResult Function( RsRemoteFsWriteEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress() when progress != null:
return progress(_that);case RsRemoteFsWriteEvent_Completed() when completed != null:
return completed(_that);case RsRemoteFsWriteEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRemoteFsWriteEvent_Progress value)  progress,required TResult Function( RsRemoteFsWriteEvent_Completed value)  completed,required TResult Function( RsRemoteFsWriteEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress():
return progress(_that);case RsRemoteFsWriteEvent_Completed():
return completed(_that);case RsRemoteFsWriteEvent_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRemoteFsWriteEvent_Progress value)?  progress,TResult? Function( RsRemoteFsWriteEvent_Completed value)?  completed,TResult? Function( RsRemoteFsWriteEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress() when progress != null:
return progress(_that);case RsRemoteFsWriteEvent_Completed() when completed != null:
return completed(_that);case RsRemoteFsWriteEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt bytesWritten)?  progress,TResult Function( BigInt bytesWritten)?  completed,TResult Function( RsRemoteFsClientError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress() when progress != null:
return progress(_that.bytesWritten);case RsRemoteFsWriteEvent_Completed() when completed != null:
return completed(_that.bytesWritten);case RsRemoteFsWriteEvent_Failed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt bytesWritten)  progress,required TResult Function( BigInt bytesWritten)  completed,required TResult Function( RsRemoteFsClientError error)  failed,}) {final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress():
return progress(_that.bytesWritten);case RsRemoteFsWriteEvent_Completed():
return completed(_that.bytesWritten);case RsRemoteFsWriteEvent_Failed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt bytesWritten)?  progress,TResult? Function( BigInt bytesWritten)?  completed,TResult? Function( RsRemoteFsClientError error)?  failed,}) {final _that = this;
switch (_that) {
case RsRemoteFsWriteEvent_Progress() when progress != null:
return progress(_that.bytesWritten);case RsRemoteFsWriteEvent_Completed() when completed != null:
return completed(_that.bytesWritten);case RsRemoteFsWriteEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsRemoteFsWriteEvent_Progress extends RsRemoteFsWriteEvent {
  const RsRemoteFsWriteEvent_Progress({required this.bytesWritten}): super._();
  

 final  BigInt bytesWritten;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsWriteEvent_ProgressCopyWith<RsRemoteFsWriteEvent_Progress> get copyWith => _$RsRemoteFsWriteEvent_ProgressCopyWithImpl<RsRemoteFsWriteEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsWriteEvent_Progress&&(identical(other.bytesWritten, bytesWritten) || other.bytesWritten == bytesWritten));
}


@override
int get hashCode => Object.hash(runtimeType,bytesWritten);

@override
String toString() {
  return 'RsRemoteFsWriteEvent.progress(bytesWritten: $bytesWritten)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsWriteEvent_ProgressCopyWith<$Res> implements $RsRemoteFsWriteEventCopyWith<$Res> {
  factory $RsRemoteFsWriteEvent_ProgressCopyWith(RsRemoteFsWriteEvent_Progress value, $Res Function(RsRemoteFsWriteEvent_Progress) _then) = _$RsRemoteFsWriteEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 BigInt bytesWritten
});




}
/// @nodoc
class _$RsRemoteFsWriteEvent_ProgressCopyWithImpl<$Res>
    implements $RsRemoteFsWriteEvent_ProgressCopyWith<$Res> {
  _$RsRemoteFsWriteEvent_ProgressCopyWithImpl(this._self, this._then);

  final RsRemoteFsWriteEvent_Progress _self;
  final $Res Function(RsRemoteFsWriteEvent_Progress) _then;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytesWritten = null,}) {
  return _then(RsRemoteFsWriteEvent_Progress(
bytesWritten: null == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRemoteFsWriteEvent_Completed extends RsRemoteFsWriteEvent {
  const RsRemoteFsWriteEvent_Completed({required this.bytesWritten}): super._();
  

 final  BigInt bytesWritten;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsWriteEvent_CompletedCopyWith<RsRemoteFsWriteEvent_Completed> get copyWith => _$RsRemoteFsWriteEvent_CompletedCopyWithImpl<RsRemoteFsWriteEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsWriteEvent_Completed&&(identical(other.bytesWritten, bytesWritten) || other.bytesWritten == bytesWritten));
}


@override
int get hashCode => Object.hash(runtimeType,bytesWritten);

@override
String toString() {
  return 'RsRemoteFsWriteEvent.completed(bytesWritten: $bytesWritten)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsWriteEvent_CompletedCopyWith<$Res> implements $RsRemoteFsWriteEventCopyWith<$Res> {
  factory $RsRemoteFsWriteEvent_CompletedCopyWith(RsRemoteFsWriteEvent_Completed value, $Res Function(RsRemoteFsWriteEvent_Completed) _then) = _$RsRemoteFsWriteEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 BigInt bytesWritten
});




}
/// @nodoc
class _$RsRemoteFsWriteEvent_CompletedCopyWithImpl<$Res>
    implements $RsRemoteFsWriteEvent_CompletedCopyWith<$Res> {
  _$RsRemoteFsWriteEvent_CompletedCopyWithImpl(this._self, this._then);

  final RsRemoteFsWriteEvent_Completed _self;
  final $Res Function(RsRemoteFsWriteEvent_Completed) _then;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytesWritten = null,}) {
  return _then(RsRemoteFsWriteEvent_Completed(
bytesWritten: null == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRemoteFsWriteEvent_Failed extends RsRemoteFsWriteEvent {
  const RsRemoteFsWriteEvent_Failed({required this.error}): super._();
  

 final  RsRemoteFsClientError error;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRemoteFsWriteEvent_FailedCopyWith<RsRemoteFsWriteEvent_Failed> get copyWith => _$RsRemoteFsWriteEvent_FailedCopyWithImpl<RsRemoteFsWriteEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRemoteFsWriteEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RsRemoteFsWriteEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RsRemoteFsWriteEvent_FailedCopyWith<$Res> implements $RsRemoteFsWriteEventCopyWith<$Res> {
  factory $RsRemoteFsWriteEvent_FailedCopyWith(RsRemoteFsWriteEvent_Failed value, $Res Function(RsRemoteFsWriteEvent_Failed) _then) = _$RsRemoteFsWriteEvent_FailedCopyWithImpl;
@useResult
$Res call({
 RsRemoteFsClientError error
});


$RsRemoteFsClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$RsRemoteFsWriteEvent_FailedCopyWithImpl<$Res>
    implements $RsRemoteFsWriteEvent_FailedCopyWith<$Res> {
  _$RsRemoteFsWriteEvent_FailedCopyWithImpl(this._self, this._then);

  final RsRemoteFsWriteEvent_Failed _self;
  final $Res Function(RsRemoteFsWriteEvent_Failed) _then;

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RsRemoteFsWriteEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as RsRemoteFsClientError,
  ));
}

/// Create a copy of RsRemoteFsWriteEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RsRemoteFsClientErrorCopyWith<$Res> get error {
  
  return $RsRemoteFsClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$RsUploadEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsUploadEvent()';
}


}

/// @nodoc
class $RsUploadEventCopyWith<$Res>  {
$RsUploadEventCopyWith(RsUploadEvent _, $Res Function(RsUploadEvent) __);
}


/// Adds pattern-matching-related methods to [RsUploadEvent].
extension RsUploadEventPatterns on RsUploadEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsUploadEvent_Progress value)?  progress,TResult Function( RsUploadEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsUploadEvent_Progress value)  progress,required TResult Function( RsUploadEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that);case RsUploadEvent_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsUploadEvent_Progress value)?  progress,TResult? Function( RsUploadEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( double progress)?  progress,TResult Function( RsHttpClientError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( double progress)  progress,required TResult Function( RsHttpClientError error)  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that.progress);case RsUploadEvent_Failed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( double progress)?  progress,TResult? Function( RsHttpClientError error)?  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsUploadEvent_Progress extends RsUploadEvent {
  const RsUploadEvent_Progress({required this.progress}): super._();
  

 final  double progress;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_ProgressCopyWith<RsUploadEvent_Progress> get copyWith => _$RsUploadEvent_ProgressCopyWithImpl<RsUploadEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'RsUploadEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_ProgressCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_ProgressCopyWith(RsUploadEvent_Progress value, $Res Function(RsUploadEvent_Progress) _then) = _$RsUploadEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 double progress
});




}
/// @nodoc
class _$RsUploadEvent_ProgressCopyWithImpl<$Res>
    implements $RsUploadEvent_ProgressCopyWith<$Res> {
  _$RsUploadEvent_ProgressCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Progress _self;
  final $Res Function(RsUploadEvent_Progress) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(RsUploadEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RsUploadEvent_Failed extends RsUploadEvent {
  const RsUploadEvent_Failed({required this.error}): super._();
  

 final  RsHttpClientError error;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_FailedCopyWith<RsUploadEvent_Failed> get copyWith => _$RsUploadEvent_FailedCopyWithImpl<RsUploadEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RsUploadEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_FailedCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_FailedCopyWith(RsUploadEvent_Failed value, $Res Function(RsUploadEvent_Failed) _then) = _$RsUploadEvent_FailedCopyWithImpl;
@useResult
$Res call({
 RsHttpClientError error
});


$RsHttpClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$RsUploadEvent_FailedCopyWithImpl<$Res>
    implements $RsUploadEvent_FailedCopyWith<$Res> {
  _$RsUploadEvent_FailedCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Failed _self;
  final $Res Function(RsUploadEvent_Failed) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RsUploadEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as RsHttpClientError,
  ));
}

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RsHttpClientErrorCopyWith<$Res> get error {
  
  return $RsHttpClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
