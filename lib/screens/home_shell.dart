import 'dart:async';

import 'package:flutter/material.dart';

import '../sauvegarde_auto.dart';
import '../state.dart';
import 'aide_screen.dart';
import 'lots_screen.dart';
import 'rapports_screen.dart';
import 'settings_screen.dart';
import 'vente_screen.dart';

/// Navigation principale : Vente, Lots, Rapports, Réglages.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(SauvegardeAuto.rattraper(appState.repo));
    WidgetsBinding.instance.addPostFrameCallback((_) => _guideSiPremiereFois());
  }

  /// Au tout premier lancement (rien d'importé, guide jamais vu), affiche le guide.
  Future<void> _guideSiPremiereFois() async {
    final repo = appState.repo;
    if (await repo.getSetting(cleGuideVu) != null) return;
    if ((await repo.lots()).isNotEmpty) {
      // Utilisateur existant : pas de guide d'accueil.
      await repo.setSetting(cleGuideVu, '1');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AideScreen(premiereFois: true)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SauvegardeAuto.rattraper(appState.repo));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          VenteScreen(surReglages: () => setState(() => _index = 3)),
          LotsScreen(surVendre: () => setState(() => _index = 0)),
          const RapportsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: 'Vente',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number_rounded),
            label: 'Lots',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Rapports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }
}
