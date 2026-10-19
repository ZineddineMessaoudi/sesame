import 'package:hive_ce/hive_ce.dart';

import '../../features/gate/data/models/gate_command.dart';
import '../../features/gate/data/models/gate_snapshot.dart';
import '../../features/gate/data/models/gate_state.dart';

part 'hive_adapters.g.dart';

/// Adapters Hive générés (`dart run build_runner build`) : un seul endroit
/// liste les types persistés. Ne jamais réordonner, seulement ajouter à la fin :
/// les typeId sont écrits sur le disque.
@GenerateAdapters([
  AdapterSpec<GateStatus>(),
  AdapterSpec<GateState>(),
  AdapterSpec<GateSnapshot>(),
  // Ajoutés pour l'outbox : une commande en attente survit à la fermeture de l'app.
  AdapterSpec<GateAction>(),
  AdapterSpec<GateCommand>(),
])
// ignore: unused_element
void _hiveAdapters() {}
