import 'package:flutter/material.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:useful_tools/useful_tools.dart';
import 'package:common/common.dart';

import '../controller/clash_connection_controller.dart';

class ClashConnections extends StatefulWidget {
  const ClashConnections({super.key});

  @override
  State<ClashConnections> createState() => _ClashConnectionsState();
}

class _ClashConnectionsState extends State<ClashConnections> {
  late ClashConnectionController clashConnectionsNotifier;
  late ScrollController controller;

  @override
  void initState() {
    super.initState();
    controller = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clashConnectionsNotifier = context.getType();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ((context) {
      final data = clashConnectionsNotifier.connections;
      final connections = data?.connections;
      if (data == null) return loadingIndicator();
      if (connections == null) {
        return reloadBotton(clashConnectionsNotifier.watchConnections);
      }

      return ListViewBuilder(
        scrollController: controller,
        itemCount: connections.length,
        itemBuilder: (context, index) {
          final item = connections[index];
          if (item == null) return const SizedBox.shrink();
          final metadata = item.metadata;
          final destination = metadata?.host?.isNotEmpty == true
              ? metadata!.host!
              : metadata?.destinationIP ?? 'Unknown destination';
          final chain = item.chains?.isNotEmpty == true
              ? item.chains!.first.toString()
              : 'Direct';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: InkButton(
              backgroundColor: const Color(0xFFD6D6D6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              borderRadius: BorderRadius.circular(6),
              overlayColor: const Color(0x2EA1A0A0),
              onPressed: () => _showConnectionDetails(context, item),
              child: Row(
                children: [
                  const Icon(Icons.public, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${metadata?.network ?? '未知网络'} · $chain · ↓${_formatBytes(item.download)}  ↑${_formatBytes(item.upload)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          );
        },
      );
    }).cs;
  }

  void _showConnectionDetails(
    BuildContext context,
    ConnectionsConnections connection,
  ) {
    showCenterDialog<void>(
      context,
      BaseDialog(
        title: 'Connection details',
        center: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Container(
            padding: .symmetric(horizontal: 12.w),
            alignment: .centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                12.verticalSpace,
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detail('Host', connection.metadata?.host),
                        _detail('Network', connection.metadata?.network),
                        _detail('Type', connection.metadata?.type),
                        _detail(
                          'Source',
                          _endpoint(
                            connection.metadata?.sourceIP,
                            connection.metadata?.sourcePort,
                          ),
                        ),
                        _detail(
                          'Destination',
                          _endpoint(
                            connection.metadata?.destinationIP,
                            connection.metadata?.destinationPort,
                          ),
                        ),
                        _detail('DNS mode', connection.metadata?.dnsMode),
                        _detail('Proxy chain', connection.chains?.join(' → ')),
                        _detail('Rule', connection.rule),
                        _detail('Rule payload', connection.rulePayload),
                        _detail('Started', _formatStarted(connection.start)),
                        _detail('Downloaded', _formatBytes(connection.download)),
                        _detail('Uploaded', _formatBytes(connection.upload)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        leftLabel: 'Cancel',
        rightLabel: 'Close connection',
        leftVoidCallback: () => Navigator.of(context).pop(),
        rightVoidCallback: connection.id == null
            ? null
            : () async {
                try {
                  await clashConnectionsNotifier.closeConnection(
                    connection.id!,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not close connection.'),
                    ),
                  );
                }
              },
      ),
    );
  }

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }

  String _endpoint(String? address, String? port) {
    if (address == null || address.isEmpty) return '';
    return port == null || port.isEmpty ? address : '$address:$port';
  }

  String? _formatStarted(String? value) {
    if (value == null || value.isEmpty) return value;
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    return formatDateYMdHms(date);
  }

  String _formatBytes(int? bytes) {
    final value = bytes ?? 0;
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '$value B';
  }
}
