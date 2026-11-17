// GENERATED CODE - DO NOT MODIFY BY HAND

part of '_g.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MihomoFallbackFilter _$MihomoFallbackFilterFromJson(
  Map<String, dynamic> json,
) => MihomoFallbackFilter(
  geoip: json['geoip'] as bool?,
  geoipCode: json['geoip-code'] as String?,
  ipcidr: (json['ipcidr'] as List<dynamic>?)?.map((e) => e as String).toList(),
  domain: (json['domain'] as List<dynamic>?)?.map((e) => e as String).toList(),
  geosite: (json['geosite'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$MihomoFallbackFilterToJson(
  MihomoFallbackFilter instance,
) => <String, dynamic>{
  'geoip': ?instance.geoip,
  'geoip-code': ?instance.geoipCode,
  'ipcidr': ?instance.ipcidr,
  'domain': ?instance.domain,
  'geosite': ?instance.geosite,
};

MihomoDnsConfig _$MihomoDnsConfigFromJson(Map<String, dynamic> json) =>
    MihomoDnsConfig(
      enable: json['enable'] as bool? ?? true,
      preferH3: json['prefer-h3'] as bool?,
      ipv6: json['ipv6'] as bool? ?? false,
      enhancedMode: json['enhanced-mode'] as String? ?? 'fake-ip',
      fakeIpRange: json['fake-ip-range'] as String? ?? '198.18.0.1/16',
      defaultNameserver:
          (json['default-nameserver'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['223.5.5.5', '1.1.1.1'],
      nameserver:
          (json['nameserver'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['223.5.5.5', '1.1.1.1', '119.29.29.29'],
      ipv6Timeout: (json['ipv6-timeout'] as num?)?.toInt(),
      useHosts: json['use-hosts'] as bool?,
      useSystemHosts: json['use-system-hosts'] as bool?,
      respectRules: json['respect-rules'] as bool?,
      fallback: (json['fallback'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      fallbackFilter: json['fallback-filter'] == null
          ? null
          : MihomoFallbackFilter.fromJson(
              json['fallback-filter'] as Map<String, dynamic>,
            ),
      listen: json['listen'] as String?,
      listenRoutingMark: (json['listen-routing-mark'] as num?)?.toInt(),
      fakeIpRange6: json['fake-ip-range6'] as String?,
      fakeIpFilter: (json['fake-ip-filter'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      fakeIpFilterMode: json['fake-ip-filter-mode'] as String?,
      fakeIpTtl: (json['fake-ip-ttl'] as num?)?.toInt(),
      cacheAlgorithm: json['cache-algorithm'] as String?,
      cacheMaxSize: (json['cache-max-size'] as num?)?.toInt(),
      nameserverPolicy: json['nameserver-policy'] as Map<String, dynamic>?,
      proxyServerNameserver: (json['proxy-server-nameserver'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      proxyServerNameserverPolicy:
          json['proxy-server-nameserver-policy'] as Map<String, dynamic>?,
      directNameserver: (json['direct-nameserver'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      directNameserverFollowPolicy:
          json['direct-nameserver-follow-policy'] as bool?,
    );

Map<String, dynamic> _$MihomoDnsConfigToJson(MihomoDnsConfig instance) =>
    <String, dynamic>{
      'enable': instance.enable,
      'prefer-h3': ?instance.preferH3,
      'ipv6': instance.ipv6,
      'ipv6-timeout': ?instance.ipv6Timeout,
      'use-hosts': ?instance.useHosts,
      'use-system-hosts': ?instance.useSystemHosts,
      'respect-rules': ?instance.respectRules,
      'nameserver': instance.nameserver,
      'fallback': ?instance.fallback,
      'fallback-filter': ?instance.fallbackFilter?.toJson(),
      'listen': ?instance.listen,
      'listen-routing-mark': ?instance.listenRoutingMark,
      'enhanced-mode': ?instance.enhancedMode,
      'fake-ip-range': ?instance.fakeIpRange,
      'fake-ip-range6': ?instance.fakeIpRange6,
      'fake-ip-filter': ?instance.fakeIpFilter,
      'fake-ip-filter-mode': ?instance.fakeIpFilterMode,
      'fake-ip-ttl': ?instance.fakeIpTtl,
      'default-nameserver': ?instance.defaultNameserver,
      'cache-algorithm': ?instance.cacheAlgorithm,
      'cache-max-size': ?instance.cacheMaxSize,
      'nameserver-policy': ?instance.nameserverPolicy,
      'proxy-server-nameserver': ?instance.proxyServerNameserver,
      'proxy-server-nameserver-policy': ?instance.proxyServerNameserverPolicy,
      'direct-nameserver': ?instance.directNameserver,
      'direct-nameserver-follow-policy': ?instance.directNameserverFollowPolicy,
    };

MihomoTunConfig _$MihomoTunConfigFromJson(
  Map<String, dynamic> json,
) => MihomoTunConfig(
  enable: json['enable'] as bool? ?? true,
  device: json['device'] as String? ?? 'clashy',
  stack: json['stack'] as String? ?? 'mixed',
  fileDescriptor: (json['file-descriptor'] as num?)?.toInt(),
  mtu: (json['mtu'] as num?)?.toInt(),
  gso: json['gso'] as bool?,
  gsoMaxSize: (json['gso-max-size'] as num?)?.toInt(),
  inet6Address: (json['inet6-address'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  dnsHijack: (json['dns-hijack'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  autoRoute: json['auto-route'] as bool?,
  autoDetectInterface: json['auto-detect-interface'] as bool?,
  strictRoute: json['strict-route'] as bool?,
  loopbackAddress: (json['loopback-address'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  routeAddress: (json['route-address'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  routeAddressSet: (json['route-address-set'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  routeExcludeAddress: (json['route-exclude-address'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  routeExcludeAddressSet: (json['route-exclude-address-set'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  iproute2TableIndex: (json['iproute2-table-index'] as num?)?.toInt(),
  iproute2RuleIndex: (json['iproute2-rule-index'] as num?)?.toInt(),
  autoRedirect: json['auto-redirect'] as bool?,
  autoRedirectInputMark: (json['auto-redirect-input-mark'] as num?)?.toInt(),
  autoRedirectOutputMark: (json['auto-redirect-output-mark'] as num?)?.toInt(),
  autoRedirectIproute2FallbackRuleIndex:
      (json['auto-redirect-iproute2-fallback-rule-index'] as num?)?.toInt(),
  endpointIndependentNat: json['endpoint-independent-nat'] as bool?,
  udpTimeout: (json['udp-timeout'] as num?)?.toInt(),
  includeInterface: (json['include-interface'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  excludeInterface: (json['exclude-interface'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  includeUid: (json['include-uid'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  includeUidRange: (json['include-uid-range'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  excludeUid: (json['exclude-uid'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  excludeUidRange: (json['exclude-uid-range'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  includePackage: (json['include-package'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  excludePackage: (json['exclude-package'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  disableIcmpForwarding: json['disable-icmp-forwarding'] as bool?,
);

Map<String, dynamic> _$MihomoTunConfigToJson(MihomoTunConfig instance) =>
    <String, dynamic>{
      'enable': instance.enable,
      'device': instance.device,
      'stack': instance.stack,
      'file-descriptor': ?instance.fileDescriptor,
      'mtu': ?instance.mtu,
      'gso': ?instance.gso,
      'gso-max-size': ?instance.gsoMaxSize,
      'inet6-address': ?instance.inet6Address,
      'dns-hijack': ?instance.dnsHijack,
      'auto-route': ?instance.autoRoute,
      'auto-detect-interface': ?instance.autoDetectInterface,
      'strict-route': ?instance.strictRoute,
      'loopback-address': ?instance.loopbackAddress,
      'route-address': ?instance.routeAddress,
      'route-address-set': ?instance.routeAddressSet,
      'route-exclude-address': ?instance.routeExcludeAddress,
      'route-exclude-address-set': ?instance.routeExcludeAddressSet,
      'iproute2-table-index': ?instance.iproute2TableIndex,
      'iproute2-rule-index': ?instance.iproute2RuleIndex,
      'auto-redirect': ?instance.autoRedirect,
      'auto-redirect-input-mark': ?instance.autoRedirectInputMark,
      'auto-redirect-output-mark': ?instance.autoRedirectOutputMark,
      'auto-redirect-iproute2-fallback-rule-index':
          ?instance.autoRedirectIproute2FallbackRuleIndex,
      'endpoint-independent-nat': ?instance.endpointIndependentNat,
      'udp-timeout': ?instance.udpTimeout,
      'include-interface': ?instance.includeInterface,
      'exclude-interface': ?instance.excludeInterface,
      'include-uid': ?instance.includeUid,
      'include-uid-range': ?instance.includeUidRange,
      'exclude-uid': ?instance.excludeUid,
      'exclude-uid-range': ?instance.excludeUidRange,
      'include-package': ?instance.includePackage,
      'exclude-package': ?instance.excludePackage,
      'disable-icmp-forwarding': ?instance.disableIcmpForwarding,
    };

MihomoSnifferConfig _$MihomoSnifferConfigFromJson(Map<String, dynamic> json) =>
    MihomoSnifferConfig(
      enable: json['enable'] as bool?,
      forceDnsMapping: json['force-dns-mapping'] as bool?,
      parsePureIp: json['parse-pure-ip'] as bool?,
      overrideDestination: json['override-destination'] as bool?,
      forceDomain: (json['force-domain'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      skipSrcAddress: (json['skip-src-address'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      skipDstAddress: (json['skip-dst-address'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      skipDomain: (json['skip-domain'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      sniffers: json['sniff'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$MihomoSnifferConfigToJson(
  MihomoSnifferConfig instance,
) => <String, dynamic>{
  'enable': ?instance.enable,
  'force-dns-mapping': ?instance.forceDnsMapping,
  'parse-pure-ip': ?instance.parsePureIp,
  'override-destination': ?instance.overrideDestination,
  'force-domain': ?instance.forceDomain,
  'skip-src-address': ?instance.skipSrcAddress,
  'skip-dst-address': ?instance.skipDstAddress,
  'skip-domain': ?instance.skipDomain,
  'sniff': ?instance.sniffers,
};

MihomoProxyGroup _$MihomoProxyGroupFromJson(Map<String, dynamic> json) =>
    MihomoProxyGroup(
      name: json['name'] as String,
      type: json['type'] as String,
      proxies: (json['proxies'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      use: (json['use'] as List<dynamic>?)?.map((e) => e as String).toList(),
      url: json['url'] as String?,
      interval: (json['interval'] as num?)?.toInt(),
      timeout: (json['timeout'] as num?)?.toInt(),
      lazy: json['lazy'] as bool?,
      tolerance: (json['tolerance'] as num?)?.toInt(),
      expectedStatus: json['expected-status'] as String?,
      includeAll: json['include-all'] as bool?,
      includeAllProxies: json['include-all-proxies'] as bool?,
      includeAllProviders: json['include-all-providers'] as bool?,
      defaultSelected: json['default-selected'] as String?,
      filter: json['filter'] as String?,
      excludeFilter: json['exclude-filter'] as String?,
    );

Map<String, dynamic> _$MihomoProxyGroupToJson(MihomoProxyGroup instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'proxies': ?instance.proxies,
      'use': ?instance.use,
      'url': ?instance.url,
      'interval': ?instance.interval,
      'timeout': ?instance.timeout,
      'lazy': ?instance.lazy,
      'tolerance': ?instance.tolerance,
      'expected-status': ?instance.expectedStatus,
      'include-all': ?instance.includeAll,
      'include-all-proxies': ?instance.includeAllProxies,
      'include-all-providers': ?instance.includeAllProviders,
      'default-selected': ?instance.defaultSelected,
      'filter': ?instance.filter,
      'exclude-filter': ?instance.excludeFilter,
    };

MihomoRootConfig _$MihomoRootConfigFromJson(
  Map<String, dynamic> json,
) => MihomoRootConfig(
  port: (json['port'] as num?)?.toInt() ?? 0,
  socksPort: (json['socks-port'] as num?)?.toInt() ?? 0,
  mixedPort: (json['mixed-port'] as num?)?.toInt() ?? 7890,
  redirPort: (json['redir-port'] as num?)?.toInt() ?? 7892,
  tproxyPort: (json['tproxy-port'] as num?)?.toInt(),
  allowLan: json['allow-lan'] as bool? ?? false,
  bindAddress: json['bind-address'] as String?,
  lanAllowedIps: (json['lan-allowed-ips'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  lanDisallowedIps: (json['lan-disallowed-ips'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  authentication: (json['authentication'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  skipAuthPrefixes: (json['skip-auth-prefixes'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  mode: json['mode'] as String? ?? "rule",
  logLevel: json['log-level'] as String? ?? "info",
  ipv6: json['ipv6'] as bool? ?? false,
  unifiedDelay: json['unified-delay'] as bool?,
  tcpConcurrent: json['tcp-concurrent'] as bool?,
  interfaceName: json['interface-name'] as String?,
  routingMark: (json['routing-mark'] as num?)?.toInt(),
  inboundTfo: json['inbound-tfo'] as bool?,
  inboundMptcp: json['inbound-mptcp'] as bool?,
  keepAliveInterval: (json['keep-alive-interval'] as num?)?.toInt(),
  keepAliveIdle: (json['keep-alive-idle'] as num?)?.toInt(),
  disableKeepAlive: json['disable-keep-alive'] as bool?,
  findProcessMode: json['find-process-mode'] as String?,
  externalController: json['external-controller'] as String?,
  externalUi: json['external-ui'] as String?,
  externalUiUrl: json['external-ui-url'] as String?,
  secret: json['secret'] as String?,
  allowOrigins: (json['allow-origins'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  geoAutoUpdate: json['geo-auto-update'] as bool?,
  geodataMode: json['geodata-mode'] as bool?,
  geoxUrl: json['geox-url'] as Map<String, dynamic>?,
  hosts: json['hosts'] as Map<String, dynamic>?,
  profile: json['profile'] as Map<String, dynamic>?,
  dns: json['dns'] == null
      ? const .new()
      : MihomoDnsConfig.fromJson(json['dns'] as Map<String, dynamic>),
  tun: json['tun'] == null
      ? const .new()
      : MihomoTunConfig.fromJson(json['tun'] as Map<String, dynamic>),
  sniffer: json['sniffer'] == null
      ? null
      : MihomoSnifferConfig.fromJson(json['sniffer'] as Map<String, dynamic>),
  proxies: json['proxies'] as List<dynamic>?,
  proxyGroups: (json['proxy-groups'] as List<dynamic>?)
      ?.map((e) => MihomoProxyGroup.fromJson(e as Map<String, dynamic>))
      .toList(),
  rules: (json['rules'] as List<dynamic>?)?.map((e) => e as String).toList(),
  proxyProviders: json['proxy-providers'] as Map<String, dynamic>?,
  ruleProviders: json['rule-providers'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$MihomoRootConfigToJson(MihomoRootConfig instance) =>
    <String, dynamic>{
      'port': instance.port,
      'socks-port': instance.socksPort,
      'mixed-port': instance.mixedPort,
      'redir-port': instance.redirPort,
      'tproxy-port': ?instance.tproxyPort,
      'allow-lan': instance.allowLan,
      'bind-address': ?instance.bindAddress,
      'lan-allowed-ips': ?instance.lanAllowedIps,
      'lan-disallowed-ips': ?instance.lanDisallowedIps,
      'authentication': ?instance.authentication,
      'skip-auth-prefixes': ?instance.skipAuthPrefixes,
      'mode': instance.mode,
      'log-level': instance.logLevel,
      'ipv6': instance.ipv6,
      'unified-delay': ?instance.unifiedDelay,
      'tcp-concurrent': ?instance.tcpConcurrent,
      'interface-name': ?instance.interfaceName,
      'routing-mark': ?instance.routingMark,
      'inbound-tfo': ?instance.inboundTfo,
      'inbound-mptcp': ?instance.inboundMptcp,
      'keep-alive-interval': ?instance.keepAliveInterval,
      'keep-alive-idle': ?instance.keepAliveIdle,
      'disable-keep-alive': ?instance.disableKeepAlive,
      'find-process-mode': ?instance.findProcessMode,
      'external-controller': ?instance.externalController,
      'external-ui': ?instance.externalUi,
      'external-ui-url': ?instance.externalUiUrl,
      'secret': ?instance.secret,
      'allow-origins': ?instance.allowOrigins,
      'geo-auto-update': ?instance.geoAutoUpdate,
      'geodata-mode': ?instance.geodataMode,
      'geox-url': ?instance.geoxUrl,
      'hosts': ?instance.hosts,
      'profile': ?instance.profile,
      'dns': instance.dns.toJson(),
      'tun': instance.tun.toJson(),
      'sniffer': ?instance.sniffer?.toJson(),
      'proxies': ?instance.proxies,
      'proxy-groups': ?instance.proxyGroups?.map((e) => e.toJson()).toList(),
      'rules': ?instance.rules,
      'proxy-providers': ?instance.proxyProviders,
      'rule-providers': ?instance.ruleProviders,
    };

ProfileScriptModel _$ProfileScriptModelFromJson(Map<String, dynamic> json) =>
    ProfileScriptModel(
      script: json['script'] as String? ?? '',
      name: json['name'] as String? ?? '',
      id: json['id'] as String,
    );

Map<String, dynamic> _$ProfileScriptModelToJson(ProfileScriptModel instance) =>
    <String, dynamic>{
      'script': instance.script,
      'name': instance.name,
      'id': instance.id,
    };

WindowRect _$WindowRectFromJson(Map<String, dynamic> json) => WindowRect(
  top: (json['top'] as num?)?.toDouble() ?? 0,
  left: (json['left'] as num?)?.toDouble() ?? 0,
  right: (json['right'] as num?)?.toDouble() ?? 0,
  bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$WindowRectToJson(WindowRect instance) =>
    <String, dynamic>{
      'top': instance.top,
      'left': instance.left,
      'right': instance.right,
      'bottom': instance.bottom,
    };
