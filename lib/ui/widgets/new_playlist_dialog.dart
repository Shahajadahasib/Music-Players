import 'package:flutter/material.dart';

/// Alert dialog with a text field. The [TextEditingController] lives in [State]
/// so it is disposed after the route removes this widget (not when [showDialog]'s
/// future completes, which can be before the exit animation finishes).
class NewPlaylistDialog extends StatefulWidget {
  const NewPlaylistDialog({super.key});

  @override
  State<NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<NewPlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.pop<String?>(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<String?>(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<String?>(context, _controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
