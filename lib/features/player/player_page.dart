import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/history_store.dart';

/// 播放页：libmpv + 进度记忆 + 音轨/字幕/倍速。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.path, this.title});

  final String path;
  final String? title;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final _history = HistoryStore();
  Timer? _ticker;
  Duration _resumeAt = Duration.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
  }

  Future<void> _open() async {
    _resumeAt = await _history.position(widget.path);
    await _player.open(Media(widget.path), play: true);
    if (_resumeAt > const Duration(seconds: 3)) {
      await _player.seek(_resumeAt);
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _savePosition() async {
    final pos = _player.state.position;
    if (pos > Duration.zero) {
      await _history.save(widget.path, pos);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _savePosition();
    _player.dispose();
    super.dispose();
  }

  Future<void> _showTracks() async {
    final tracks = _player.state.tracks;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const _SectionTitle('音轨'),
              for (final t in tracks.audio)
                ListTile(
                  title: Text(t.title ?? t.language ?? '音轨 ${t.id}'),
                  trailing: t.id == _player.state.track.audio.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    _player.setAudioTrack(t);
                    Navigator.pop(sheetContext);
                  },
                ),
              const Divider(),
              const _SectionTitle('字幕'),
              ListTile(
                title: const Text('关闭字幕'),
                trailing: _player.state.track.subtitle.id == 'no'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(sheetContext);
                },
              ),
              for (final t in tracks.subtitle)
                ListTile(
                  title: Text(t.title ?? t.language ?? '字幕 ${t.id}'),
                  trailing: t.id == _player.state.track.subtitle.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    _player.setSubtitleTrack(t);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _showSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            for (final s in speeds)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text('${s}x'),
                  selected: (_player.state.rate - s).abs() < 0.01,
                  onSelected: (_) {
                    _player.setRate(s);
                    Navigator.pop(sheetContext);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? widget.path.split('/').last, maxLines: 1),
        actions: [
          IconButton(
            tooltip: '音轨/字幕',
            icon: const Icon(Icons.subtitles_outlined),
            onPressed: _showTracks,
          ),
          IconButton(
            tooltip: '倍速',
            icon: const Icon(Icons.speed),
            onPressed: _showSpeed,
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Video(controller: _controller, controls: NoVideoControls),
          ),
          if (!_ready) const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Controls(player: _player),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, posSnap) {
          return StreamBuilder<Duration>(
            stream: player.stream.duration,
            builder: (context, durSnap) {
              final duration = durSnap.data ?? Duration.zero;
              final position = posSnap.data ?? Duration.zero;
              final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
              return Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    builder: (context, snap) => IconButton(
                      color: Colors.white,
                      icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow),
                      onPressed: () => player.playOrPause(),
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => player.seek(
                      position - const Duration(seconds: 10) < Duration.zero
                          ? Duration.zero
                          : position - const Duration(seconds: 10),
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => player.seek(position + const Duration(seconds: 10)),
                  ),
                  Text(_fmt(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: position.inMilliseconds.toDouble().clamp(0, max),
                      max: max,
                      onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(_fmt(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}