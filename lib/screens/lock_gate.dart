import 'package:flutter/material.dart';

import '../security.dart';
import '../state.dart';
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
  DateTime? _pauseLe;
  bool _bioActive = false;
  bool _bioEnCours = false;

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
    final bio = defini && await Biometrie.active() && await Biometrie.disponible();
    if (!mounted) return;
    setState(() {
      _bioActive = bio;
      _etat = defini ? _Etat.verrouille : _Etat.creation;
    });
    if (defini) _oublierVendeurProtege();
    if (bio) _essayerBiometrie();
  }

  /// Fenêtre système d'empreinte / visage. En cas d'échec ou d'annulation,
  /// le PIN reste affiché et utilisable.
  Future<void> _essayerBiometrie() async {
    if (_bioEnCours || _etat != _Etat.verrouille) return;
    _bioEnCours = true;
    final ok = await Biometrie.demander('Déverrouillez Mtandao');
    _bioEnCours = false;
    if (!mounted || !ok || _etat != _Etat.verrouille) return;
    await PinService.reinitialiserEchecs();
    if (!mounted) return;
    setState(() {
      _etat = _Etat.ouvert;
      _erreur = false;
      _message = null;
    });
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
        _oublierVendeurProtege();
        _rafraichirBio();
      }
    }
  }

  /// À chaque verrouillage, un vendeur protégé par un code est « déconnecté » :
  /// son code sera redemandé pour vendre en son nom.
  Future<void> _oublierVendeurProtege() async {
    await appState.repo.oublierVendeurActifProtege();
    appState.changed();
  }

  Future<void> _rafraichirBio() async {
    final bio = await Biometrie.active() && await Biometrie.disponible();
    if (!mounted) return;
    setState(() => _bioActive = bio);
    if (bio) _essayerBiometrie();
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
    // Les échecs et les blocages sont enregistrés : rouvrir l'application ne
    // permet pas de réessayer sans attendre.
    final r = await PinService.verifierAvecLimite(pin);
    if (!mounted) return;
    switch (r.statut) {
      case StatutPin.correct:
        setState(() {
          _etat = _Etat.ouvert;
          _erreur = false;
          _message = null;
        });
      case StatutPin.bloque:
        setState(() {
          _erreur = true;
          _message = 'Trop d\'essais. Réessayez dans ${PinService.dureeLisible(r.secondes)}.';
        });
      case StatutPin.incorrect:
        setState(() {
          _erreur = true;
          _message = r.essaisRestants <= 2
              ? 'Code incorrect. Encore ${r.essaisRestants} essai${r.essaisRestants > 1 ? 's' : ''} avant un blocage.'
              : 'Code incorrect.';
        });
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
          body: Center(
            child: Image.asset('assets/logo.png',
                height: 96, excludeFromSemantics: true),
          ),
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
                Image.asset('assets/logo.png',
                    height: 88, excludeFromSemantics: true),
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
                if (_etat == _Etat.verrouille && _bioActive) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _essayerBiometrie,
                    style: TextButton.styleFrom(
                        minimumSize: const Size(48, 52)),
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Empreinte ou visage'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
