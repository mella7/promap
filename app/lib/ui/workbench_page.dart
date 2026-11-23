import 'package:flutter/material.dart';

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
                        title: 'Camera - tap to light a spot',
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
              _Controls(bench: _bench),
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
