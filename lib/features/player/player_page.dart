import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/history_store.dart';
import '../../data/library_store.dart';
import '../../playback/playback_bridge.dart';

/// 播放页：libmpv + 手势 + 进度记忆 + 音轨/字幕/倍速 + 后台播放。
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
  final _library = LibraryStore();
  bool _fav = false;
  Timer? _ticker;
  int _tick = 0;
  Duration _resumeAt = Duration.zero;
  bool _ready = false;

  // 手势状态
  double _volume = 1.0;
  double _brightness = 0.5;
  double? _seekPreview; // 秒
  String? _hint;
  Timer? _hintTimer;
  double _savedRate = 1.0;

  String get _title => widget.title ?? widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    PlaybackBridge.init();
    PlaybackBridge.onCommand = _handleCommand;
    PlaybackBridge.keepScreenOn(true);
    _library.isFavorite(widget.path).then((v) {
      if (mounted) setState(() => _fav = v);
    });
    _open();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  Future<void> _open() async {
    _resumeAt = await _history.position(widget.path);
    await _player.open(Media(widget.path), play: true);
    if (_resumeAt > const Duration(seconds: 3)) {
      await _player.seek(_resumeAt);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    await PlaybackBridge.start(title: _title, duration: _player.state.duration);
  }

  void _onTick() {
    _tick++;
    PlaybackBridge.update(
      title: _title,
      position: _player.state.position,
      duration: _player.state.duration,
      playing: _player.state.playing,
    );
    if (_tick % 5 == 0) {
      final pos = _player.state.position;
      if (pos > Duration.zero) {
        _history.save(widget.path, pos);
        _library.recordPlay(widget.path, _title, pos, _player.state.duration);
      }
    }
  }

  void _handleCommand(String cmd) {
    if (!mounted) return;
    if (cmd == 'play') {
      _player.play();
    } else if (cmd == 'pause') {
      _player.pause();
    } else if (cmd == 'stop') {
      Navigator.of(context).maybePop();
    } else if (cmd == 'back') {
      _seekRelative(const Duration(seconds: -10));
    } else if (cmd == 'forward') {
      _seekRelative(const Duration(seconds: 10));
    } else if (cmd.startsWith('seek:')) {
      final ms = int.tryParse(cmd.substring(5)) ?? 0;
      _player.seek(Duration(milliseconds: ms));
    }
    setState(() {});
  }

  void _seekRelative(Duration delta) {
    final target = _player.state.position + delta;
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hintTimer?.cancel();
    PlaybackBridge.onCommand = null;
    PlaybackBridge.stop();
    PlaybackBridge.keepScreenOn(false);
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
                  trailing: t.id == _player.state.track.audio.id ? const Icon(Icons.check) : null,
                  onTap: () {
                    _player.setAudioTrack(t);
                    Navigator.pop(sheetContext);
                  },
                ),
              const Divider(),
              const _SectionTitle('字幕'),
              ListTile(
                title: const Text('关闭字幕'),
                trailing: _player.state.track.subtitle.id == 'no' ? const Icon(Icons.check) : null,
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(sheetContext);
                },
              ),
              for (final t in tracks.subtitle)
                ListTile(
                  title: Text(t.title ?? t.language ?? '字幕 ${t.id}'),
                  trailing: t.id == _player.state.track.subtitle.id ? const Icon(Icons.check) : null,
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

  Future<void> _addToPlaylist() async {
    final lists = await _library.playlists();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('加入播放列表'),
        children: [
          for (final p in lists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, p.name),
              child: Text(p.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '__new__'),
            child: const Text('+ 新建播放列表'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    var name = selected;
    if (name == '__new__') {
      final controller = TextEditingController();
      name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('新建播放列表'),
          content: TextField(controller: controller, decoration: const InputDecoration(labelText: '名称')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('创建'),
            ),
          ],
        ),
      ) ?? '';
      if (name.isEmpty) return;
      await _library.createPlaylist(name);
    }
    await _library.addToPlaylist(name, widget.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入 $name')));
  }

  void _showInfo() {
    final s = _player.state;
    final v = s.videoParams;
    final a = s.audioParams;
    final rows = <String>[
      '标题：${_title}',
      '地址：${widget.path}',
      '时长：${_fmt(s.duration)}',
      if (v != null) '分辨率：${v.w}×${v.h}  像素格式：${v.pixelformat}',
      if (a != null) '音频：${a.format} ${a.sampleRate}Hz ${a.channelCount}ch',
      '音轨数：${s.tracks.audio.length}  字幕数：${s.tracks.subtitle.length}',
      '倍速：${s.rate}x',
    ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('媒体信息'),
        content: SelectableText(rows.join('\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {}),
        onDoubleTap: () {
          _player.playOrPause();
          _showHint(_player.state.playing ? '暂停' : '播放');
        },
        onLongPressStart: (_) {
          _savedRate = _player.state.rate;
          _player.setRate(2.0);
          _showHint('2x 快进');
        },
        onLongPressEnd: (_) {
          _player.setRate(_savedRate);
        },
        onHorizontalDragStart: (d) => setState(() => _seekPreview = _player.state.position.inSeconds.toDouble()),
        onHorizontalDragUpdate: (d) {
          final total = _player.state.duration.inSeconds.toDouble();
          setState(() {
            _seekPreview = ((_seekPreview ?? 0) - d.delta.dx / 4).clamp(0.0, total == 0 ? 1.0 : total);
            _hint = _fmt(Duration(seconds: _seekPreview!.toInt()));
          });
        },
        onHorizontalDragEnd: (_) {
          if (_seekPreview != null) {
            _player.seek(Duration(seconds: _seekPreview!.toInt()));
          }
          setState(() => _seekPreview = null);
          _showHint(' ');
        },
        onVerticalDragStart: (d) => setState(() {}),
        onVerticalDragUpdate: (d) async {
          final isLeft = d.globalPosition.dx < MediaQuery.of(context).size.width / 2;
          final delta = -d.delta.dy / 300;
          if (isLeft) {
            _brightness = (_brightness + delta).clamp(0.01, 1.0);
            await PlaybackBridge.setBrightness(_brightness);
            _showHint('亮度 ${(_brightness * 100).round()}%');
          } else {
            _volume = (_volume + delta).clamp(0.0, 1.0);
            await PlaybackBridge.setVolume(_volume);
            _showHint('音量 ${(_volume * 100).round()}%');
          }
        },
        child: Stack(
          children: [
            Center(child: Video(controller: _controller, controls: NoVideoControls)),
            if (!_ready) const Center(child: CircularProgressIndicator()),
            if (_hint != null)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_hint!, style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AppBar(
                backgroundColor: Colors.black26,
                foregroundColor: Colors.white,
                title: Text(_title, maxLines: 1),
                actions: [
                  IconButton(
                    tooltip: '收藏',
                    icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                        color: _fav ? Colors.redAccent : null),
                    onPressed: () async {
                      final added = await _library.toggleFavorite(widget.path);
                      if (mounted) setState(() => _fav = added);
                    },
                  ),
                  IconButton(
                    tooltip: '加入播放列表',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: _addToPlaylist,
                  ),
                  IconButton(tooltip: '信息', icon: const Icon(Icons.info_outline), onPressed: _showInfo),
                  IconButton(tooltip: '音轨/字幕', icon: const Icon(Icons.subtitles_outlined), onPressed: _showTracks),
                  IconButton(tooltip: '倍速', icon: const Icon(Icons.speed), onPressed: _showSpeed),
                ],
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _Controls(player: _player)),
          ],
        ),
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
                    onPressed: () {
                      final t = player.state.position - const Duration(seconds: 10);
                      player.seek(t < Duration.zero ? Duration.zero : t);
                    },
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => player.seek(player.state.position + const Duration(seconds: 10)),
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

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}