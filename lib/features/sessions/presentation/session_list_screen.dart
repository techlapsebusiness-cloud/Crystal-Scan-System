import 'package:flutter/material.dart';

import 'package:microscopeapp/app_dependencies.dart';
import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/features/sessions/presentation/session_summary_screen.dart';
import 'package:microscopeapp/models/session_status.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  SessionIndex? _index;
  Object? _error;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final index = await AppScope.of(context).store.loadIndex();
      if (!mounted) {
        return;
      }
      setState(() {
        _index = index;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved sessions')),
      body: _error != null
          ? _Message(
              title: 'Sessions could not be read',
              detail: _error.toString(),
              onRetry: _reload,
            )
          : index == null
          ? const Center(child: CircularProgressIndicator())
          : index.sessions.isEmpty && index.unreadablePaths.isEmpty
          ? const _Message(
              title: 'No captures yet',
              detail: 'Finished sessions stay on this device.',
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: [
                  for (final session in index.sessions)
                    ListTile(
                      title: Text(formatTimestamp(session.createdAt)),
                      subtitle: Text(
                        '${session.savedCount} saved · ${session.failedCount} failed · '
                        '${sessionStatusLabel(session.status)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SessionSummaryScreen(session: session),
                          ),
                        );
                        await _reload();
                      },
                    ),
                  for (final path in index.unreadablePaths)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Unreadable session'),
                      subtitle: Text(path),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.onRetry});

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
