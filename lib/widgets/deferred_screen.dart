import 'package:flutter/material.dart';

/// Downloads role-specific web code only when its route is opened.
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({super.key, required this.load, required this.builder});

  final Future<void> Function() load;
  final WidgetBuilder builder;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late Future<void> _loading = Future.sync(widget.load);

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load this screen. Please try again.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() {
                    _loading = Future.sync(widget.load);
                  }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.done) {
        return widget.builder(context);
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    },
  );
}
