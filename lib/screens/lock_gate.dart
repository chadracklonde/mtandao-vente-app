import 'package:flutter/material.dart';

import '../security.dart';
import '../widgets/pin_pad.dart';

enum _Etat { chargement, creation, confirmation, verrouille, ouvert }

/// Verrouille l'application derrière le PIN : au lancement, et au retour
/// après plus d'une minute en arrière-plan. S'affiche par-dessus la navigation
/// (qui reste en place), pour ne pas interrompre un import en cours.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  static const Duration _delai = Duration(seconds: 60);

  _Etat _etat = _Etat.chargement;
  String _premierPin = '';
  bool _erreur = false;
  String? _message;
  int _echecs = 0;
  DateTime? _bloqueJusqua;
  DateTime? _pauseLe;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    final defini = await PinService.estDefini();
    if (!mounted) return;
    setState(() => _etat = defini ? _Etat.verrouille : _Etat.creation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseLe = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pauseLe;
      _pauseLe = null;
      if (_etat == _Etat.ouvert &&
          p != null &&
          DateTime.now().difference(p) > _delai) {
        setState(() {
          _etat = _Etat.verrouille;
          _erreur = false;
          _message = null;
        });
      }
    }
  }

  Future<void> _surCreation(String pin) async {
    setState(() {
      _premierPin = pin;
      _etat = _Etat.confirmation;
      _erreur = false;
      _message = null;
    });
  }

  Future<void> _surConfirmation(String pin) async {
    if (pin == _premierPin) {
      await PinService.definir(pin);
      if (!mounted) return;
      setState(() {
        _etat = _Etat.ouvert;
        _erreur = false;
        _message = null;
      });
    } else {
      setState(() {
        _etat = _Etat.creation;
        _premierPin = '';
        _erreur = true;
        _message = 'Les deux codes ne correspondent pas. Recommencez.';
      });
    }
  }

  Future<void> _surVerification(String pin) async {
    final bloque = _bloqueJusqua;
    if (bloque != null && DateTime.now().isBefore(bloque)) {
      final s = bloque.difference(DateTime.now()).inSeconds + 1;
      setState(() {
        _erreur = true;
        _message = 'Trop d\'essais. Réessayez dans $s s.';
      });
      return;
    }
    final ok = await PinService.verifier(pin);
    if (!mounted) return;
    if (ok) {
      _echecs = 0;
      setState(() {
        _etat = _Etat.ouvert;
        _erreur = false;
        _message = null;
      });
    } else {
      _echecs++;
      if (_echecs >= 5) {
        _echecs = 0;
        _bloqueJusqua = DateTime.now().add(const Duration(seconds: 30));
        setState(() {
          _erreur = true;
          _message = 'Trop d\'essais. Réessayez dans 30 s.';
        });
      } else {
        setState(() {
          _erreur = true;
          _message = 'Code incorrect.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_etat != _Etat.ouvert) Positioned.fill(child: _ecran(context)),
      ],
    );
  }

  Widget _ecran(BuildContext context) {
    final String titre;
    final Future<void> Function(String) action;
    String? message = _message;
    switch (_etat) {
      case _Etat.chargement:
        return Scaffold(
          body: Center(child: Image.asset('assets/logo.png', height: 96)),
        );
      case _Etat.creation:
        titre = 'Créez votre code PIN';
        message ??= 'Choisissez 4 chiffres pour protéger vos ventes.';
        action = _surCreation;
        break;
      case _Etat.confirmation:
        titre = 'Confirmez le code PIN';
        message ??= 'Saisissez à nouveau les 4 chiffres.';
        action = _surConfirmation;
        break;
      case _Etat.verrouille:
        titre = 'Entrez votre code PIN';
        action = _surVerification;
        break;
      case _Etat.ouvert:
        return const SizedBox.shrink();
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', height: 88),
                const SizedBox(height: 8),
                Text('Mtandao',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 28),
                PinPad(
                  key: ValueKey(_etat),
                  titre: titre,
                  message: message,
                  erreur: _erreur,
                  onComplete: action,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
