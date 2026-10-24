import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// MVP 播放页：libmpv（media_kit 封装）+ 基础控制条。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.path});

  final String path;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    await _player.open(Media(widget.path), play: true);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Text(widget.path.split('/').last, maxLines: 1),
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
