part of '_g.dart';

const _deep = DeepCollectionEquality();

// ============================================================
// DNS 回落过滤
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoFallbackFilter {
  @JsonKey(name: 'geoip')
  final bool? geoip;

  @JsonKey(name: 'geoip-code')
  final String? geoipCode;

  @JsonKey(name: 'ipcidr')
  final List<String>? ipcidr;

  @JsonKey(name: 'domain')
  final List<String>? domain;

  @JsonKey(name: 'geosite')
  final List<String>? geosite;

  const MihomoFallbackFilter({
    this.geoip,
    this.geoipCode,
    this.ipcidr,
    this.domain,
    this.geosite,
  });

  factory MihomoFallbackFilter.fromJson(Map<String, dynamic> json) =>
      _$MihomoFallbackFilterFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoFallbackFilterToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoFallbackFilter &&
          runtimeType == other.runtimeType &&
          geoip == other.geoip &&
          geoipCode == other.geoipCode &&
          _deep.equals(ipcidr, other.ipcidr) &&
          _deep.equals(domain, other.domain) &&
          _deep.equals(geosite, other.geosite);

  @override
  int get hashCode => Object.hashAll([
    geoip,
    geoipCode,
    _deep.hash(ipcidr),
    _deep.hash(domain),
    _deep.hash(geosite),
  ]);

  MihomoFallbackFilter copyWith({
    bool? geoip,
    String? geoipCode,
    List<String>? ipcidr,
    List<String>? domain,
    List<String>? geosite,
  }) {
    return MihomoFallbackFilter(
      geoip: geoip ?? this.geoip,
      geoipCode: geoipCode ?? this.geoipCode,
      ipcidr: ipcidr ?? this.ipcidr,
      domain: domain ?? this.domain,
      geosite: geosite ?? this.geosite,
    );
  }
}

// ============================================================
// DNS 配置
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoDnsConfig {
  @JsonKey(name: 'enable')
  final bool enable;

  @JsonKey(name: 'prefer-h3')
  final bool? preferH3;

  @JsonKey(name: 'ipv6')
  final bool ipv6;

  @JsonKey(name: 'ipv6-timeout')
  final int? ipv6Timeout;

  @JsonKey(name: 'use-hosts')
  final bool? useHosts;

  @JsonKey(name: 'use-system-hosts')
  final bool? useSystemHosts;

  @JsonKey(name: 'respect-rules')
  final bool? respectRules;

  @JsonKey(name: 'nameserver')
  final List<String> nameserver;

  @JsonKey(name: 'fallback')
  final List<String>? fallback;

  @JsonKey(name: 'fallback-filter')
  final MihomoFallbackFilter? fallbackFilter;

  @JsonKey(name: 'listen')
  final String? listen;

  @JsonKey(name: 'listen-routing-mark')
  final int? listenRoutingMark;

  @JsonKey(name: 'enhanced-mode')
  final String? enhancedMode;

  @JsonKey(name: 'fake-ip-range')
  final String? fakeIpRange;

  @JsonKey(name: 'fake-ip-range6')
  final String? fakeIpRange6;

  @JsonKey(name: 'fake-ip-filter')
  final List<String>? fakeIpFilter;

  @JsonKey(name: 'fake-ip-filter-mode')
  final String? fakeIpFilterMode;

  @JsonKey(name: 'fake-ip-ttl')
  final int? fakeIpTtl;

  @JsonKey(name: 'default-nameserver')
  final List<String>? defaultNameserver;

  @JsonKey(name: 'cache-algorithm')
  final String? cacheAlgorithm;

  @JsonKey(name: 'cache-max-size')
  final int? cacheMaxSize;

  @JsonKey(name: 'nameserver-policy')
  final Map<String, dynamic>? nameserverPolicy;

  @JsonKey(name: 'proxy-server-nameserver')
  final List<String>? proxyServerNameserver;

  @JsonKey(name: 'proxy-server-nameserver-policy')
  final Map<String, dynamic>? proxyServerNameserverPolicy;

  @JsonKey(name: 'direct-nameserver')
  final List<String>? directNameserver;

  @JsonKey(name: 'direct-nameserver-follow-policy')
  final bool? directNameserverFollowPolicy;

  const MihomoDnsConfig({
    this.enable = true,
    this.preferH3,
    this.ipv6 = false,
    this.enhancedMode = 'fake-ip',
    this.fakeIpRange = '198.18.0.1/16',
    this.defaultNameserver = const ['223.5.5.5', '1.1.1.1'],
    this.nameserver = const ['223.5.5.5', '1.1.1.1', '119.29.29.29'],
    this.ipv6Timeout,
    this.useHosts,
    this.useSystemHosts,
    this.respectRules,
    this.fallback,
    this.fallbackFilter,
    this.listen,
    this.listenRoutingMark,
    this.fakeIpRange6,
    this.fakeIpFilter,
    this.fakeIpFilterMode,
    this.fakeIpTtl,
    this.cacheAlgorithm,
    this.cacheMaxSize,
    this.nameserverPolicy,
    this.proxyServerNameserver,
    this.proxyServerNameserverPolicy,
    this.directNameserver,
    this.directNameserverFollowPolicy,
  });

  factory MihomoDnsConfig.fromJson(Map<String, dynamic> json) =>
      _$MihomoDnsConfigFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoDnsConfigToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoDnsConfig &&
          runtimeType == other.runtimeType &&
          enable == other.enable &&
          preferH3 == other.preferH3 &&
          ipv6 == other.ipv6 &&
          ipv6Timeout == other.ipv6Timeout &&
          useHosts == other.useHosts &&
          useSystemHosts == other.useSystemHosts &&
          respectRules == other.respectRules &&
          _deep.equals(nameserver, other.nameserver) &&
          _deep.equals(fallback, other.fallback) &&
          fallbackFilter == other.fallbackFilter &&
          listen == other.listen &&
          listenRoutingMark == other.listenRoutingMark &&
          enhancedMode == other.enhancedMode &&
          fakeIpRange == other.fakeIpRange &&
          fakeIpRange6 == other.fakeIpRange6 &&
          _deep.equals(fakeIpFilter, other.fakeIpFilter) &&
          fakeIpFilterMode == other.fakeIpFilterMode &&
          fakeIpTtl == other.fakeIpTtl &&
          _deep.equals(defaultNameserver, other.defaultNameserver) &&
          cacheAlgorithm == other.cacheAlgorithm &&
          cacheMaxSize == other.cacheMaxSize &&
          _deep.equals(nameserverPolicy, other.nameserverPolicy) &&
          _deep.equals(proxyServerNameserver, other.proxyServerNameserver) &&
          _deep.equals(
            proxyServerNameserverPolicy,
            other.proxyServerNameserverPolicy,
          ) &&
          _deep.equals(directNameserver, other.directNameserver) &&
          directNameserverFollowPolicy == other.directNameserverFollowPolicy;

  @override
  int get hashCode => Object.hashAll([
    enable,
    preferH3,
    ipv6,
    ipv6Timeout,
    useHosts,
    useSystemHosts,
    respectRules,
    _deep.hash(nameserver),
    _deep.hash(fallback),
    fallbackFilter,
    listen,
    listenRoutingMark,
    enhancedMode,
    fakeIpRange,
    fakeIpRange6,
    _deep.hash(fakeIpFilter),
    fakeIpFilterMode,
    fakeIpTtl,
    _deep.hash(defaultNameserver),
    cacheAlgorithm,
    cacheMaxSize,
    _deep.hash(nameserverPolicy),
    _deep.hash(proxyServerNameserver),
    _deep.hash(proxyServerNameserverPolicy),
    _deep.hash(directNameserver),
    directNameserverFollowPolicy,
  ]);

  MihomoDnsConfig copyWith({
    bool? enable,
    bool? preferH3,
    bool? ipv6,
    int? ipv6Timeout,
    bool? useHosts,
    bool? useSystemHosts,
    bool? respectRules,
    List<String>? nameserver,
    List<String>? fallback,
    MihomoFallbackFilter? fallbackFilter,
    String? listen,
    int? listenRoutingMark,
    String? enhancedMode,
    String? fakeIpRange,
    String? fakeIpRange6,
    List<String>? fakeIpFilter,
    String? fakeIpFilterMode,
    int? fakeIpTtl,
    List<String>? defaultNameserver,
    String? cacheAlgorithm,
    int? cacheMaxSize,
    Map<String, dynamic>? nameserverPolicy,
    List<String>? proxyServerNameserver,
    Map<String, dynamic>? proxyServerNameserverPolicy,
    List<String>? directNameserver,
    bool? directNameserverFollowPolicy,
  }) {
    return MihomoDnsConfig(
      enable: enable ?? this.enable,
      preferH3: preferH3 ?? this.preferH3,
      ipv6: ipv6 ?? this.ipv6,
      ipv6Timeout: ipv6Timeout ?? this.ipv6Timeout,
      useHosts: useHosts ?? this.useHosts,
      useSystemHosts: useSystemHosts ?? this.useSystemHosts,
      respectRules: respectRules ?? this.respectRules,
      nameserver: nameserver ?? this.nameserver,
      fallback: fallback ?? this.fallback,
      fallbackFilter: fallbackFilter ?? this.fallbackFilter,
      listen: listen ?? this.listen,
      listenRoutingMark: listenRoutingMark ?? this.listenRoutingMark,
      enhancedMode: enhancedMode ?? this.enhancedMode,
      fakeIpRange: fakeIpRange ?? this.fakeIpRange,
      fakeIpRange6: fakeIpRange6 ?? this.fakeIpRange6,
      fakeIpFilter: fakeIpFilter ?? this.fakeIpFilter,
      fakeIpFilterMode: fakeIpFilterMode ?? this.fakeIpFilterMode,
      fakeIpTtl: fakeIpTtl ?? this.fakeIpTtl,
      defaultNameserver: defaultNameserver ?? this.defaultNameserver,
      cacheAlgorithm: cacheAlgorithm ?? this.cacheAlgorithm,
      cacheMaxSize: cacheMaxSize ?? this.cacheMaxSize,
      nameserverPolicy: nameserverPolicy ?? this.nameserverPolicy,
      proxyServerNameserver:
          proxyServerNameserver ?? this.proxyServerNameserver,
      proxyServerNameserverPolicy:
          proxyServerNameserverPolicy ?? this.proxyServerNameserverPolicy,
      directNameserver: directNameserver ?? this.directNameserver,
      directNameserverFollowPolicy:
          directNameserverFollowPolicy ?? this.directNameserverFollowPolicy,
    );
  }
}

// ============================================================
// TUN 配置
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoTunConfig {
  @JsonKey(name: 'enable')
  final bool enable;

  @JsonKey(name: 'device')
  final String device;

  @JsonKey(name: 'stack')
  final String stack;

  @JsonKey(name: 'file-descriptor')
  final int? fileDescriptor;

  @JsonKey(name: 'mtu')
  final int? mtu;

  @JsonKey(name: 'gso')
  final bool? gso;

  @JsonKey(name: 'gso-max-size')
  final int? gsoMaxSize;

  @JsonKey(name: 'inet6-address')
  final List<String>? inet6Address;

  @JsonKey(name: 'dns-hijack')
  final List<String>? dnsHijack;

  @JsonKey(name: 'auto-route')
  final bool? autoRoute;

  @JsonKey(name: 'auto-detect-interface')
  final bool? autoDetectInterface;

  @JsonKey(name: 'strict-route')
  final bool? strictRoute;

  @JsonKey(name: 'loopback-address')
  final List<String>? loopbackAddress;

  @JsonKey(name: 'route-address')
  final List<String>? routeAddress;

  @JsonKey(name: 'route-address-set')
  final List<String>? routeAddressSet;

  @JsonKey(name: 'route-exclude-address')
  final List<String>? routeExcludeAddress;

  @JsonKey(name: 'route-exclude-address-set')
  final List<String>? routeExcludeAddressSet;

  @JsonKey(name: 'iproute2-table-index')
  final int? iproute2TableIndex;

  @JsonKey(name: 'iproute2-rule-index')
  final int? iproute2RuleIndex;

  @JsonKey(name: 'auto-redirect')
  final bool? autoRedirect;

  @JsonKey(name: 'auto-redirect-input-mark')
  final int? autoRedirectInputMark;

  @JsonKey(name: 'auto-redirect-output-mark')
  final int? autoRedirectOutputMark;

  @JsonKey(name: 'auto-redirect-iproute2-fallback-rule-index')
  final int? autoRedirectIproute2FallbackRuleIndex;

  @JsonKey(name: 'endpoint-independent-nat')
  final bool? endpointIndependentNat;

  @JsonKey(name: 'udp-timeout')
  final int? udpTimeout;

  @JsonKey(name: 'include-interface')
  final List<String>? includeInterface;

  @JsonKey(name: 'exclude-interface')
  final List<String>? excludeInterface;

  @JsonKey(name: 'include-uid')
  final List<int>? includeUid;

  @JsonKey(name: 'include-uid-range')
  final List<String>? includeUidRange;

  @JsonKey(name: 'exclude-uid')
  final List<int>? excludeUid;

  @JsonKey(name: 'exclude-uid-range')
  final List<String>? excludeUidRange;

  @JsonKey(name: 'include-package')
  final List<String>? includePackage;

  @JsonKey(name: 'exclude-package')
  final List<String>? excludePackage;

  @JsonKey(name: 'disable-icmp-forwarding')
  final bool? disableIcmpForwarding;

  const MihomoTunConfig({
    this.enable = true,
    this.device = 'clashy',
    this.stack = 'mixed',
    this.fileDescriptor,
    this.mtu,
    this.gso,
    this.gsoMaxSize,
    this.inet6Address,
    this.dnsHijack,
    this.autoRoute,
    this.autoDetectInterface,
    this.strictRoute,
    this.loopbackAddress,
    this.routeAddress,
    this.routeAddressSet,
    this.routeExcludeAddress,
    this.routeExcludeAddressSet,
    this.iproute2TableIndex,
    this.iproute2RuleIndex,
    this.autoRedirect,
    this.autoRedirectInputMark,
    this.autoRedirectOutputMark,
    this.autoRedirectIproute2FallbackRuleIndex,
    this.endpointIndependentNat,
    this.udpTimeout,
    this.includeInterface,
    this.excludeInterface,
    this.includeUid,
    this.includeUidRange,
    this.excludeUid,
    this.excludeUidRange,
    this.includePackage,
    this.excludePackage,
    this.disableIcmpForwarding,
  });

  factory MihomoTunConfig.fromJson(Map<String, dynamic> json) =>
      _$MihomoTunConfigFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoTunConfigToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoTunConfig &&
          runtimeType == other.runtimeType &&
          enable == other.enable &&
          device == other.device &&
          stack == other.stack &&
          fileDescriptor == other.fileDescriptor &&
          mtu == other.mtu &&
          gso == other.gso &&
          gsoMaxSize == other.gsoMaxSize &&
          _deep.equals(inet6Address, other.inet6Address) &&
          _deep.equals(dnsHijack, other.dnsHijack) &&
          autoRoute == other.autoRoute &&
          autoDetectInterface == other.autoDetectInterface &&
          strictRoute == other.strictRoute &&
          _deep.equals(loopbackAddress, other.loopbackAddress) &&
          _deep.equals(routeAddress, other.routeAddress) &&
          _deep.equals(routeAddressSet, other.routeAddressSet) &&
          _deep.equals(routeExcludeAddress, other.routeExcludeAddress) &&
          _deep.equals(routeExcludeAddressSet, other.routeExcludeAddressSet) &&
          iproute2TableIndex == other.iproute2TableIndex &&
          iproute2RuleIndex == other.iproute2RuleIndex &&
          autoRedirect == other.autoRedirect &&
          autoRedirectInputMark == other.autoRedirectInputMark &&
          autoRedirectOutputMark == other.autoRedirectOutputMark &&
          autoRedirectIproute2FallbackRuleIndex ==
              other.autoRedirectIproute2FallbackRuleIndex &&
          endpointIndependentNat == other.endpointIndependentNat &&
          udpTimeout == other.udpTimeout &&
          _deep.equals(includeInterface, other.includeInterface) &&
          _deep.equals(excludeInterface, other.excludeInterface) &&
          _deep.equals(includeUid, other.includeUid) &&
          _deep.equals(includeUidRange, other.includeUidRange) &&
          _deep.equals(excludeUid, other.excludeUid) &&
          _deep.equals(excludeUidRange, other.excludeUidRange) &&
          _deep.equals(includePackage, other.includePackage) &&
          _deep.equals(excludePackage, other.excludePackage) &&
          disableIcmpForwarding == other.disableIcmpForwarding;

  @override
  int get hashCode => Object.hashAll([
    enable,
    device,
    stack,
    fileDescriptor,
    mtu,
    gso,
    gsoMaxSize,
    _deep.hash(inet6Address),
    _deep.hash(dnsHijack),
    autoRoute,
    autoDetectInterface,
    strictRoute,
    _deep.hash(loopbackAddress),
    _deep.hash(routeAddress),
    _deep.hash(routeAddressSet),
    _deep.hash(routeExcludeAddress),
    _deep.hash(routeExcludeAddressSet),
    iproute2TableIndex,
    iproute2RuleIndex,
    autoRedirect,
    autoRedirectInputMark,
    autoRedirectOutputMark,
    autoRedirectIproute2FallbackRuleIndex,
    endpointIndependentNat,
    udpTimeout,
    _deep.hash(includeInterface),
    _deep.hash(excludeInterface),
    _deep.hash(includeUid),
    _deep.hash(includeUidRange),
    _deep.hash(excludeUid),
    _deep.hash(excludeUidRange),
    _deep.hash(includePackage),
    _deep.hash(excludePackage),
    disableIcmpForwarding,
  ]);

  /// 创建副本
  MihomoTunConfig copyWith({
    bool? enable,
    String? device,
    String? stack,
    int? fileDescriptor,
    int? mtu,
    bool? gso,
    int? gsoMaxSize,
    List<String>? inet6Address,
    List<String>? dnsHijack,
    bool? autoRoute,
    bool? autoDetectInterface,
    bool? strictRoute,
    List<String>? loopbackAddress,
    List<String>? routeAddress,
    List<String>? routeAddressSet,
    List<String>? routeExcludeAddress,
    List<String>? routeExcludeAddressSet,
    int? iproute2TableIndex,
    int? iproute2RuleIndex,
    bool? autoRedirect,
    int? autoRedirectInputMark,
    int? autoRedirectOutputMark,
    int? autoRedirectIproute2FallbackRuleIndex,
    bool? endpointIndependentNat,
    int? udpTimeout,
    List<String>? includeInterface,
    List<String>? excludeInterface,
    List<int>? includeUid,
    List<String>? includeUidRange,
    List<int>? excludeUid,
    List<String>? excludeUidRange,
    List<String>? includePackage,
    List<String>? excludePackage,
    bool? disableIcmpForwarding,
  }) {
    return MihomoTunConfig(
      enable: enable ?? this.enable,
      device: device ?? this.device,
      stack: stack ?? this.stack,
      fileDescriptor: fileDescriptor ?? this.fileDescriptor,
      mtu: mtu ?? this.mtu,
      gso: gso ?? this.gso,
      gsoMaxSize: gsoMaxSize ?? this.gsoMaxSize,
      inet6Address: inet6Address ?? this.inet6Address,
      dnsHijack: dnsHijack ?? this.dnsHijack,
      autoRoute: autoRoute ?? this.autoRoute,
      autoDetectInterface: autoDetectInterface ?? this.autoDetectInterface,
      strictRoute: strictRoute ?? this.strictRoute,
      loopbackAddress: loopbackAddress ?? this.loopbackAddress,
      routeAddress: routeAddress ?? this.routeAddress,
      routeAddressSet: routeAddressSet ?? this.routeAddressSet,
      routeExcludeAddress: routeExcludeAddress ?? this.routeExcludeAddress,
      routeExcludeAddressSet:
          routeExcludeAddressSet ?? this.routeExcludeAddressSet,
      iproute2TableIndex: iproute2TableIndex ?? this.iproute2TableIndex,
      iproute2RuleIndex: iproute2RuleIndex ?? this.iproute2RuleIndex,
      autoRedirect: autoRedirect ?? this.autoRedirect,
      autoRedirectInputMark:
          autoRedirectInputMark ?? this.autoRedirectInputMark,
      autoRedirectOutputMark:
          autoRedirectOutputMark ?? this.autoRedirectOutputMark,
      autoRedirectIproute2FallbackRuleIndex:
          autoRedirectIproute2FallbackRuleIndex ??
          this.autoRedirectIproute2FallbackRuleIndex,
      endpointIndependentNat:
          endpointIndependentNat ?? this.endpointIndependentNat,
      udpTimeout: udpTimeout ?? this.udpTimeout,
      includeInterface: includeInterface ?? this.includeInterface,
      excludeInterface: excludeInterface ?? this.excludeInterface,
      includeUid: includeUid ?? this.includeUid,
      includeUidRange: includeUidRange ?? this.includeUidRange,
      excludeUid: excludeUid ?? this.excludeUid,
      excludeUidRange: excludeUidRange ?? this.excludeUidRange,
      includePackage: includePackage ?? this.includePackage,
      excludePackage: excludePackage ?? this.excludePackage,
      disableIcmpForwarding:
          disableIcmpForwarding ?? this.disableIcmpForwarding,
    );
  }
}

// ============================================================
// 嗅探器配置
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoSnifferConfig {
  @JsonKey(name: 'enable')
  final bool? enable;

  @JsonKey(name: 'force-dns-mapping')
  final bool? forceDnsMapping;

  @JsonKey(name: 'parse-pure-ip')
  final bool? parsePureIp;

  @JsonKey(name: 'override-destination')
  final bool? overrideDestination;

  @JsonKey(name: 'force-domain')
  final List<String>? forceDomain;

  @JsonKey(name: 'skip-src-address')
  final List<String>? skipSrcAddress;

  @JsonKey(name: 'skip-dst-address')
  final List<String>? skipDstAddress;

  @JsonKey(name: 'skip-domain')
  final List<String>? skipDomain;

  @JsonKey(name: 'sniff')
  final Map<String, dynamic>? sniffers;

  const MihomoSnifferConfig({
    this.enable,
    this.forceDnsMapping,
    this.parsePureIp,
    this.overrideDestination,
    this.forceDomain,
    this.skipSrcAddress,
    this.skipDstAddress,
    this.skipDomain,
    this.sniffers,
  });

  factory MihomoSnifferConfig.fromJson(Map<String, dynamic> json) =>
      _$MihomoSnifferConfigFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoSnifferConfigToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoSnifferConfig &&
          runtimeType == other.runtimeType &&
          enable == other.enable &&
          forceDnsMapping == other.forceDnsMapping &&
          parsePureIp == other.parsePureIp &&
          overrideDestination == other.overrideDestination &&
          _deep.equals(forceDomain, other.forceDomain) &&
          _deep.equals(skipSrcAddress, other.skipSrcAddress) &&
          _deep.equals(skipDstAddress, other.skipDstAddress) &&
          _deep.equals(skipDomain, other.skipDomain) &&
          _deep.equals(sniffers, other.sniffers);

  @override
  int get hashCode => Object.hashAll([
    enable,
    forceDnsMapping,
    parsePureIp,
    overrideDestination,
    _deep.hash(forceDomain),
    _deep.hash(skipSrcAddress),
    _deep.hash(skipDstAddress),
    _deep.hash(skipDomain),
    _deep.hash(sniffers),
  ]);

  MihomoSnifferConfig copyWith({
    bool? enable,
    bool? forceDnsMapping,
    bool? parsePureIp,
    bool? overrideDestination,
    List<String>? forceDomain,
    List<String>? skipSrcAddress,
    List<String>? skipDstAddress,
    List<String>? skipDomain,
    Map<String, dynamic>? sniffers,
  }) {
    return MihomoSnifferConfig(
      enable: enable ?? this.enable,
      forceDnsMapping: forceDnsMapping ?? this.forceDnsMapping,
      parsePureIp: parsePureIp ?? this.parsePureIp,
      overrideDestination: overrideDestination ?? this.overrideDestination,
      forceDomain: forceDomain ?? this.forceDomain,
      skipSrcAddress: skipSrcAddress ?? this.skipSrcAddress,
      skipDstAddress: skipDstAddress ?? this.skipDstAddress,
      skipDomain: skipDomain ?? this.skipDomain,
      sniffers: sniffers ?? this.sniffers,
    );
  }
}

// ============================================================
// 代理组配置
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoProxyGroup {
  @JsonKey(name: 'name')
  final String name;

  @JsonKey(name: 'type')
  final String type;

  @JsonKey(name: 'proxies')
  final List<String>? proxies;

  @JsonKey(name: 'use')
  final List<String>? use;

  @JsonKey(name: 'url')
  final String? url;

  @JsonKey(name: 'interval')
  final int? interval;

  @JsonKey(name: 'timeout')
  final int? timeout;

  @JsonKey(name: 'lazy')
  final bool? lazy;

  @JsonKey(name: 'tolerance')
  final int? tolerance;

  @JsonKey(name: 'expected-status')
  final String? expectedStatus;

  @JsonKey(name: 'include-all')
  final bool? includeAll;

  @JsonKey(name: 'include-all-proxies')
  final bool? includeAllProxies;

  @JsonKey(name: 'include-all-providers')
  final bool? includeAllProviders;

  @JsonKey(name: 'default-selected')
  final String? defaultSelected;

  @JsonKey(name: 'filter')
  final String? filter;

  @JsonKey(name: 'exclude-filter')
  final String? excludeFilter;

  const MihomoProxyGroup({
    required this.name,
    required this.type,
    this.proxies,
    this.use,
    this.url,
    this.interval,
    this.timeout,
    this.lazy,
    this.tolerance,
    this.expectedStatus,
    this.includeAll,
    this.includeAllProxies,
    this.includeAllProviders,
    this.defaultSelected,
    this.filter,
    this.excludeFilter,
  });

  factory MihomoProxyGroup.fromJson(Map<String, dynamic> json) =>
      _$MihomoProxyGroupFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoProxyGroupToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoProxyGroup &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          type == other.type &&
          _deep.equals(proxies, other.proxies) &&
          _deep.equals(use, other.use) &&
          url == other.url &&
          interval == other.interval &&
          timeout == other.timeout &&
          lazy == other.lazy &&
          tolerance == other.tolerance &&
          expectedStatus == other.expectedStatus &&
          includeAll == other.includeAll &&
          includeAllProxies == other.includeAllProxies &&
          includeAllProviders == other.includeAllProviders &&
          defaultSelected == other.defaultSelected &&
          filter == other.filter &&
          excludeFilter == other.excludeFilter;

  @override
  int get hashCode => Object.hashAll([
    name,
    type,
    _deep.hash(proxies),
    _deep.hash(use),
    url,
    interval,
    timeout,
    lazy,
    tolerance,
    expectedStatus,
    includeAll,
    includeAllProxies,
    includeAllProviders,
    defaultSelected,
    filter,
    excludeFilter,
  ]);

  MihomoProxyGroup copyWith({
    String? name,
    String? type,
    List<String>? proxies,
    List<String>? use,
    String? url,
    int? interval,
    int? timeout,
    bool? lazy,
    int? tolerance,
    String? expectedStatus,
    bool? includeAll,
    bool? includeAllProxies,
    bool? includeAllProviders,
    String? defaultSelected,
    String? filter,
    String? excludeFilter,
  }) {
    return MihomoProxyGroup(
      name: name ?? this.name,
      type: type ?? this.type,
      proxies: proxies ?? this.proxies,
      use: use ?? this.use,
      url: url ?? this.url,
      interval: interval ?? this.interval,
      timeout: timeout ?? this.timeout,
      lazy: lazy ?? this.lazy,
      tolerance: tolerance ?? this.tolerance,
      expectedStatus: expectedStatus ?? this.expectedStatus,
      includeAll: includeAll ?? this.includeAll,
      includeAllProxies: includeAllProxies ?? this.includeAllProxies,
      includeAllProviders: includeAllProviders ?? this.includeAllProviders,
      defaultSelected: defaultSelected ?? this.defaultSelected,
      filter: filter ?? this.filter,
      excludeFilter: excludeFilter ?? this.excludeFilter,
    );
  }
}

// ============================================================
// 根配置
// ============================================================
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MihomoRootConfig {
  // --- 代理端口 ---
  @JsonKey(name: 'port')
  final int port;

  @JsonKey(name: 'socks-port')
  final int socksPort;

  @JsonKey(name: 'mixed-port')
  final int mixedPort;

  @JsonKey(name: 'redir-port')
  final int redirPort;

  @JsonKey(name: 'tproxy-port')
  final int? tproxyPort;

  // --- 局域网访问 ---
  @JsonKey(name: 'allow-lan')
  final bool allowLan;

  @JsonKey(name: 'bind-address')
  final String? bindAddress;

  @JsonKey(name: 'lan-allowed-ips')
  final List<String>? lanAllowedIps;

  @JsonKey(name: 'lan-disallowed-ips')
  final List<String>? lanDisallowedIps;

  // --- 认证 ---
  @JsonKey(name: 'authentication')
  final List<String>? authentication;

  @JsonKey(name: 'skip-auth-prefixes')
  final List<String>? skipAuthPrefixes;

  // --- 运行模式 ---
  @JsonKey(name: 'mode')
  final String mode;

  @JsonKey(name: 'log-level')
  final String logLevel;

  // --- 网络与性能 ---
  @JsonKey(name: 'ipv6')
  final bool ipv6;

  @JsonKey(name: 'unified-delay')
  final bool? unifiedDelay;

  @JsonKey(name: 'tcp-concurrent')
  final bool? tcpConcurrent;

  @JsonKey(name: 'interface-name')
  final String? interfaceName;

  @JsonKey(name: 'routing-mark')
  final int? routingMark;

  @JsonKey(name: 'inbound-tfo')
  final bool? inboundTfo;

  @JsonKey(name: 'inbound-mptcp')
  final bool? inboundMptcp;

  // --- TCP Keep-Alive ---
  @JsonKey(name: 'keep-alive-interval')
  final int? keepAliveInterval;

  @JsonKey(name: 'keep-alive-idle')
  final int? keepAliveIdle;

  @JsonKey(name: 'disable-keep-alive')
  final bool? disableKeepAlive;

  // --- 进程匹配 ---
  @JsonKey(name: 'find-process-mode')
  final String? findProcessMode;

  // --- 外部控制 API ---
  @JsonKey(name: 'external-controller')
  final String? externalController;

  @JsonKey(name: 'external-ui')
  final String? externalUi;

  @JsonKey(name: 'external-ui-url')
  final String? externalUiUrl;

  @JsonKey(name: 'secret')
  final String? secret;

  @JsonKey(name: 'allow-origins')
  final List<String>? allowOrigins;

  // --- 地理数据 ---
  @JsonKey(name: 'geo-auto-update')
  final bool? geoAutoUpdate;

  @JsonKey(name: 'geodata-mode')
  final bool? geodataMode;

  @JsonKey(name: 'geox-url')
  final Map<String, dynamic>? geoxUrl;

  // --- 其他 ---
  @JsonKey(name: 'hosts')
  final Map<String, dynamic>? hosts;

  @JsonKey(name: 'profile')
  final Map<String, dynamic>? profile;

  // --- 嵌套配置块 ---
  @JsonKey(name: 'dns')
  final MihomoDnsConfig dns;

  @JsonKey(name: 'tun')
  final MihomoTunConfig tun;

  @JsonKey(name: 'sniffer')
  final MihomoSnifferConfig? sniffer;

  // --- 数组/映射配置 ---
  @JsonKey(name: 'proxies')
  final List<dynamic>? proxies;

  @JsonKey(name: 'proxy-groups')
  final List<MihomoProxyGroup>? proxyGroups;

  @JsonKey(name: 'rules')
  final List<String>? rules;

  @JsonKey(name: 'proxy-providers')
  final Map<String, dynamic>? proxyProviders;

  @JsonKey(name: 'rule-providers')
  final Map<String, dynamic>? ruleProviders;

  const MihomoRootConfig({
    this.port = 0,
    this.socksPort = 0,
    this.mixedPort = 7890,
    this.redirPort = 7892,
    this.tproxyPort,
    this.allowLan = false,
    this.bindAddress,
    this.lanAllowedIps,
    this.lanDisallowedIps,
    this.authentication,
    this.skipAuthPrefixes,
    this.mode = "rule",
    this.logLevel = "info",
    this.ipv6 = false,
    this.unifiedDelay,
    this.tcpConcurrent,
    this.interfaceName,
    this.routingMark,
    this.inboundTfo,
    this.inboundMptcp,
    this.keepAliveInterval,
    this.keepAliveIdle,
    this.disableKeepAlive,
    this.findProcessMode,
    this.externalController,
    this.externalUi,
    this.externalUiUrl,
    this.secret,
    this.allowOrigins,
    this.geoAutoUpdate,
    this.geodataMode,
    this.geoxUrl,
    this.hosts,
    this.profile,
    this.dns = const .new(),
    this.tun = const .new(),
    this.sniffer,
    this.proxies,
    this.proxyGroups,
    this.rules,
    this.proxyProviders,
    this.ruleProviders,
  });

  factory MihomoRootConfig.fromJson(Map<String, dynamic> json) =>
      _$MihomoRootConfigFromJson(json);

  Map<String, dynamic> toJson() => _$MihomoRootConfigToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MihomoRootConfig &&
          runtimeType == other.runtimeType &&
          port == other.port &&
          socksPort == other.socksPort &&
          mixedPort == other.mixedPort &&
          redirPort == other.redirPort &&
          tproxyPort == other.tproxyPort &&
          allowLan == other.allowLan &&
          bindAddress == other.bindAddress &&
          _deep.equals(lanAllowedIps, other.lanAllowedIps) &&
          _deep.equals(lanDisallowedIps, other.lanDisallowedIps) &&
          _deep.equals(authentication, other.authentication) &&
          _deep.equals(skipAuthPrefixes, other.skipAuthPrefixes) &&
          mode == other.mode &&
          logLevel == other.logLevel &&
          ipv6 == other.ipv6 &&
          unifiedDelay == other.unifiedDelay &&
          tcpConcurrent == other.tcpConcurrent &&
          interfaceName == other.interfaceName &&
          routingMark == other.routingMark &&
          inboundTfo == other.inboundTfo &&
          inboundMptcp == other.inboundMptcp &&
          keepAliveInterval == other.keepAliveInterval &&
          keepAliveIdle == other.keepAliveIdle &&
          disableKeepAlive == other.disableKeepAlive &&
          findProcessMode == other.findProcessMode &&
          externalController == other.externalController &&
          externalUi == other.externalUi &&
          externalUiUrl == other.externalUiUrl &&
          secret == other.secret &&
          _deep.equals(allowOrigins, other.allowOrigins) &&
          geoAutoUpdate == other.geoAutoUpdate &&
          geodataMode == other.geodataMode &&
          _deep.equals(geoxUrl, other.geoxUrl) &&
          _deep.equals(hosts, other.hosts) &&
          _deep.equals(profile, other.profile) &&
          dns == other.dns &&
          tun == other.tun &&
          sniffer == other.sniffer &&
          _deep.equals(proxies, other.proxies) &&
          _deep.equals(proxyGroups, other.proxyGroups) &&
          _deep.equals(rules, other.rules) &&
          _deep.equals(proxyProviders, other.proxyProviders) &&
          _deep.equals(ruleProviders, other.ruleProviders);

  @override
  int get hashCode => Object.hashAll([
    port,
    socksPort,
    mixedPort,
    redirPort,
    tproxyPort,
    allowLan,
    bindAddress,
    _deep.hash(lanAllowedIps),
    _deep.hash(lanDisallowedIps),
    _deep.hash(authentication),
    _deep.hash(skipAuthPrefixes),
    mode,
    logLevel,
    ipv6,
    unifiedDelay,
    tcpConcurrent,
    interfaceName,
    routingMark,
    inboundTfo,
    inboundMptcp,
    keepAliveInterval,
    keepAliveIdle,
    disableKeepAlive,
    findProcessMode,
    externalController,
    externalUi,
    externalUiUrl,
    secret,
    _deep.hash(allowOrigins),
    geoAutoUpdate,
    geodataMode,
    _deep.hash(geoxUrl),
    _deep.hash(hosts),
    _deep.hash(profile),
    dns,
    tun,
    sniffer,
    _deep.hash(proxies),
    _deep.hash(proxyGroups),
    _deep.hash(rules),
    _deep.hash(proxyProviders),
    _deep.hash(ruleProviders),
  ]);

  MihomoRootConfig copyWith({
    int? port,
    int? socksPort,
    int? mixedPort,
    int? redirPort,
    int? tproxyPort,
    bool? allowLan,
    String? bindAddress,
    List<String>? lanAllowedIps,
    List<String>? lanDisallowedIps,
    List<String>? authentication,
    List<String>? skipAuthPrefixes,
    String? mode,
    String? logLevel,
    bool? ipv6,
    bool? unifiedDelay,
    bool? tcpConcurrent,
    String? interfaceName,
    int? routingMark,
    bool? inboundTfo,
    bool? inboundMptcp,
    int? keepAliveInterval,
    int? keepAliveIdle,
    bool? disableKeepAlive,
    String? findProcessMode,
    String? externalController,
    String? externalUi,
    String? externalUiUrl,
    String? secret,
    List<String>? allowOrigins,
    bool? geoAutoUpdate,
    bool? geodataMode,
    Map<String, dynamic>? geoxUrl,
    Map<String, dynamic>? hosts,
    Map<String, dynamic>? profile,
    MihomoDnsConfig? dns,
    MihomoTunConfig? tun,
    MihomoSnifferConfig? sniffer,
    List<dynamic>? proxies,
    List<MihomoProxyGroup>? proxyGroups,
    List<String>? rules,
    Map<String, dynamic>? proxyProviders,
    Map<String, dynamic>? ruleProviders,
  }) {
    return MihomoRootConfig(
      port: port ?? this.port,
      socksPort: socksPort ?? this.socksPort,
      mixedPort: mixedPort ?? this.mixedPort,
      redirPort: redirPort ?? this.redirPort,
      tproxyPort: tproxyPort ?? this.tproxyPort,
      allowLan: allowLan ?? this.allowLan,
      bindAddress: bindAddress ?? this.bindAddress,
      lanAllowedIps: lanAllowedIps ?? this.lanAllowedIps,
      lanDisallowedIps: lanDisallowedIps ?? this.lanDisallowedIps,
      authentication: authentication ?? this.authentication,
      skipAuthPrefixes: skipAuthPrefixes ?? this.skipAuthPrefixes,
      mode: mode ?? this.mode,
      logLevel: logLevel ?? this.logLevel,
      ipv6: ipv6 ?? this.ipv6,
      unifiedDelay: unifiedDelay ?? this.unifiedDelay,
      tcpConcurrent: tcpConcurrent ?? this.tcpConcurrent,
      interfaceName: interfaceName ?? this.interfaceName,
      routingMark: routingMark ?? this.routingMark,
      inboundTfo: inboundTfo ?? this.inboundTfo,
      inboundMptcp: inboundMptcp ?? this.inboundMptcp,
      keepAliveInterval: keepAliveInterval ?? this.keepAliveInterval,
      keepAliveIdle: keepAliveIdle ?? this.keepAliveIdle,
      disableKeepAlive: disableKeepAlive ?? this.disableKeepAlive,
      findProcessMode: findProcessMode ?? this.findProcessMode,
      externalController: externalController ?? this.externalController,
      externalUi: externalUi ?? this.externalUi,
      externalUiUrl: externalUiUrl ?? this.externalUiUrl,
      secret: secret ?? this.secret,
      allowOrigins: allowOrigins ?? this.allowOrigins,
      geoAutoUpdate: geoAutoUpdate ?? this.geoAutoUpdate,
      geodataMode: geodataMode ?? this.geodataMode,
      geoxUrl: geoxUrl ?? this.geoxUrl,
      hosts: hosts ?? this.hosts,
      profile: profile ?? this.profile,
      dns: dns ?? this.dns,
      tun: tun ?? this.tun,
      sniffer: sniffer ?? this.sniffer,
      proxies: proxies ?? this.proxies,
      proxyGroups: proxyGroups ?? this.proxyGroups,
      rules: rules ?? this.rules,
      proxyProviders: proxyProviders ?? this.proxyProviders,
      ruleProviders: ruleProviders ?? this.ruleProviders,
    );
  }
}
