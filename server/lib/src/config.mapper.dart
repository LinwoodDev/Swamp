// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'config.dart';

class SwampConfigMapper extends ClassMapperBase<SwampConfig> {
  SwampConfigMapper._();

  static SwampConfigMapper? _instance;
  static SwampConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SwampConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SwampConfig';

  static String _$description(SwampConfig v) => v.description;
  static const Field<SwampConfig, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
    def: "",
  );
  static int _$maxPlayers(SwampConfig v) => v.maxPlayers;
  static const Field<SwampConfig, int> _f$maxPlayers = Field(
    'maxPlayers',
    _$maxPlayers,
    opt: true,
    def: 1024,
  );
  static bool _$noDarkRooms(SwampConfig v) => v.noDarkRooms;
  static const Field<SwampConfig, bool> _f$noDarkRooms = Field(
    'noDarkRooms',
    _$noDarkRooms,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<SwampConfig> fields = const {
    #description: _f$description,
    #maxPlayers: _f$maxPlayers,
    #noDarkRooms: _f$noDarkRooms,
  };

  static SwampConfig _instantiate(DecodingData data) {
    return SwampConfig(
      description: data.dec(_f$description),
      maxPlayers: data.dec(_f$maxPlayers),
      noDarkRooms: data.dec(_f$noDarkRooms),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SwampConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SwampConfig>(map);
  }

  static SwampConfig fromJson(String json) {
    return ensureInitialized().decodeJson<SwampConfig>(json);
  }
}

mixin SwampConfigMappable {
  String toJson() {
    return SwampConfigMapper.ensureInitialized().encodeJson<SwampConfig>(
      this as SwampConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return SwampConfigMapper.ensureInitialized().encodeMap<SwampConfig>(
      this as SwampConfig,
    );
  }

  SwampConfigCopyWith<SwampConfig, SwampConfig, SwampConfig> get copyWith =>
      _SwampConfigCopyWithImpl<SwampConfig, SwampConfig>(
        this as SwampConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SwampConfigMapper.ensureInitialized().stringifyValue(
      this as SwampConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return SwampConfigMapper.ensureInitialized().equalsValue(
      this as SwampConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return SwampConfigMapper.ensureInitialized().hashValue(this as SwampConfig);
  }
}

extension SwampConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SwampConfig, $Out> {
  SwampConfigCopyWith<$R, SwampConfig, $Out> get $asSwampConfig =>
      $base.as((v, t, t2) => _SwampConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SwampConfigCopyWith<$R, $In extends SwampConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? description, int? maxPlayers, bool? noDarkRooms});
  SwampConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SwampConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SwampConfig, $Out>
    implements SwampConfigCopyWith<$R, SwampConfig, $Out> {
  _SwampConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SwampConfig> $mapper =
      SwampConfigMapper.ensureInitialized();
  @override
  $R call({String? description, int? maxPlayers, bool? noDarkRooms}) => $apply(
    FieldCopyWithData({
      if (description != null) #description: description,
      if (maxPlayers != null) #maxPlayers: maxPlayers,
      if (noDarkRooms != null) #noDarkRooms: noDarkRooms,
    }),
  );
  @override
  SwampConfig $make(CopyWithData data) => SwampConfig(
    description: data.get(#description, or: $value.description),
    maxPlayers: data.get(#maxPlayers, or: $value.maxPlayers),
    noDarkRooms: data.get(#noDarkRooms, or: $value.noDarkRooms),
  );

  @override
  SwampConfigCopyWith<$R2, SwampConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SwampConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

