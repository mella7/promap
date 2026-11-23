import 'package:effects/effects.dart';
import 'package:flutter/material.dart';
import 'package:scene_core/scene_core.dart';

import '../devices/output_controller.dart';
import '../devices/simulated_camera.dart';
import '../workbench.dart';
import 'camera_view.dart';
import 'output_view.dart';

class WorkbenchPage extends StatefulWidget {
  /// Pass one in tests to control timing; the page makes its own otherwise.
  final Workbench? workbench;

  const WorkbenchPage({super.key, this.workbench});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  late final Workbench _bench = widget.workbench ?? Workbench();

  @override
  void dispose() {
    if (widget.workbench == null) _bench.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('promap - simulator')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_bench, _bench.scan]),
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Panel(
                        title: 'Camera - tap to light a spot or pick a surface',
                        child: CameraView(
                          frame: _bench.cameraFrame,
                          onTap: _bench.tapCamera,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Panel(
                        title: 'Projector output',
                        child: OutputView(controller: _bench.output),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(child: _Controls(bench: _bench)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(child: Center(child: child)),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final Workbench bench;

  const _Controls({required this.bench});

  @override
  Widget build(BuildContext context) {
    final busy = bench.busy;
    final store = bench.store;
    final report = bench.report;
    final textTheme = Theme.of(context).textTheme;
    final surfaces = store.scene.surfaces;
    final selected = bench.selectedSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<SimPreset>(
              value: bench.preset,
              onChanged: busy
                  ? null
                  : (preset) {
                      if (preset != null) bench.setPreset(preset);
                    },
              items: [
                for (final preset in SimPreset.values)
                  DropdownMenuItem(value: preset, child: Text(preset.label)),
              ],
            ),
            FilledButton(
              onPressed: busy ? null : bench.startScan,
              child: const Text('Scan'),
            ),
            OutlinedButton(
              onPressed: busy || !bench.calibrated ? null : bench.findSurfaces,
              child: const Text('Find surfaces'),
            ),
            OutlinedButton(
              onPressed: busy || !store.canUndo ? null : bench.undo,
              child: const Text('Undo'),
            ),
            OutlinedButton(
              onPressed: busy || !store.canRedo ? null : bench.redo,
              child: const Text('Redo'),
            ),
            DropdownButton<String>(
              hint: const Text('Theme'),
              value: null,
              onChanged: busy || surfaces.isEmpty
                  ? null
                  : (id) {
                      final theme = id == null ? null : themeById(id);
                      if (theme != null) bench.applyTheme(theme);
                    },
              items: [
                for (final theme in themes)
                  DropdownMenuItem(value: theme.id, child: Text(theme.name)),
              ],
            ),
            OutlinedButton(
              onPressed: busy || !bench.calibrated ? null : bench.saveProject,
              child: const Text('Save'),
            ),
            OutlinedButton(
              onPressed: busy ? null : bench.openProject,
              child: const Text('Open saved'),
            ),
            if (bench.output.mode == OutputMode.white && bench.calibrated)
              TextButton(
                onPressed: busy ? null : bench.showScene,
                child: const Text('Show mapping'),
              )
            else
              TextButton(
                onPressed: busy ? null : bench.showWhite,
                child: const Text('White light'),
              ),
          ],
        ),
        if (selected != null)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Selected: ${selected.name}', style: textTheme.bodyMedium),
              DropdownButton<String>(
                value: _effectIdOf(selected) ?? _plainColour,
                onChanged: busy
                    ? null
                    : (id) => bench.setSurfaceEffect(
                        selected.id, id == _plainColour ? null : id),
                items: [
                  const DropdownMenuItem(
                      value: _plainColour, child: Text('Plain colour')),
                  for (final effect in effectLibrary)
                    DropdownMenuItem(
                        value: effect.id, child: Text(effect.name)),
                ],
              ),
            ],
          ),
        if (selected != null && selected.content is EffectContent)
          _EffectSettings(
            key: ValueKey('${selected.id}:${(selected.content as EffectContent).effect}'),
            bench: bench,
            surface: selected,
            enabled: !busy,
          ),
        const SizedBox(height: 8),
        if (bench.scan.busy) ...[
          LinearProgressIndicator(value: bench.scan.progress),
          const SizedBox(height: 4),
          Text(bench.scan.phase, style: textTheme.bodySmall),
        ] else ...[
          if (bench.finding) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
          ],
          Text(bench.status, style: textTheme.bodyMedium),
        ],
        if (report != null && !bench.scan.busy)
          Text(
            'Camera coverage ${(report.cameraCoverage * 100).toStringAsFixed(0)}%, '
            'projector coverage ${(report.projectorCoverage * 100).toStringAsFixed(0)}%, '
            'room light ${report.ambientLevel.toStringAsFixed(0)}, '
            'contrast ${report.meanContrast.toStringAsFixed(0)}',
            style: textTheme.bodySmall,
          ),
        if (surfaces.isNotEmpty)
          Text(
            'Surfaces: ${[for (final s in surfaces) s.name].join(', ')}',
            style: textTheme.bodySmall,
          ),
        Text(
          'Surfaces come from: ${bench.finder.description}',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

const _plainColour = '_plain';

/// The library effect a surface shows, or null for anything else.
String? _effectIdOf(Surface surface) {
  final content = surface.content;
  if (content is EffectContent && effectById(content.effect) != null) {
    return content.effect;
  }
  return null;
}

/// Colours offered for an effect's colour setting.
const _swatches = [
  '#FFFFFF',
  '#FF2BD6',
  '#FF5A1F',
  '#FFB000',
  '#3DFFB5',
  '#2E8BFF',
  '#7A2BFF',
  '#E83F6F',
];

/// One control per setting of the selected surface's effect. Sliders preview
/// live while dragging and save one undo step when let go.
class _EffectSettings extends StatefulWidget {
  final Workbench bench;
  final Surface surface;
  final bool enabled;

  const _EffectSettings({
    super.key,
    required this.bench,
    required this.surface,
    required this.enabled,
  });

  @override
  State<_EffectSettings> createState() => _EffectSettingsState();
}

class _EffectSettingsState extends State<_EffectSettings> {
  /// Slider values while a drag is in progress.
  final Map<String, double> _dragging = {};

  @override
  Widget build(BuildContext context) {
    final content = widget.surface.content as EffectContent;
    final spec = effectById(content.effect);
    if (spec == null) return const SizedBox.shrink();
    final values = spec.resolve(content.params);
    final id = widget.surface.id;
    final textTheme = Theme.of(context).textTheme;

    Map<String, Object?> withValue(String key, Object value) =>
        {...values, key: value};

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final param in spec.params)
          switch (param.kind) {
            ParamKind.number => SizedBox(
                width: 280,
                child: Row(
                  children: [
                    SizedBox(
                        width: 80,
                        child: Text(param.label, style: textTheme.bodySmall)),
                    Expanded(
                      child: Slider(
                        min: param.min,
                        max: param.max,
                        value: _dragging[param.key] ??
                            (values[param.key] as double),
                        onChanged: !widget.enabled
                            ? null
                            : (v) {
                                setState(() => _dragging[param.key] = v);
                                widget.bench.previewSurfaceParams(
                                    id, withValue(param.key, v));
                              },
                        onChangeEnd: !widget.enabled
                            ? null
                            : (v) {
                                _dragging.remove(param.key);
                                widget.bench.commitSurfaceParams(
                                    id, withValue(param.key, v));
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ParamKind.toggle => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(param.label, style: textTheme.bodySmall),
                  Switch(
                    value: values[param.key] as bool,
                    onChanged: !widget.enabled
                        ? null
                        : (v) => widget.bench
                            .commitSurfaceParams(id, withValue(param.key, v)),
                  ),
                ],
              ),
            ParamKind.color => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(param.label, style: textTheme.bodySmall),
                  const SizedBox(width: 6),
                  for (final hex in _swatches)
                    _Swatch(
                      hex: hex,
                      selected: values[param.key] == hex,
                      onTap: !widget.enabled
                          ? null
                          : () => widget.bench
                              .commitSurfaceParams(id, withValue(param.key, hex)),
                    ),
                ],
              ),
          },
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback? onTap;

  const _Swatch({required this.hex, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
