import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security.dart';

/// Clavier numérique pour saisir un PIN à 4 chiffres.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.titre,
    this.message,
    this.erreur = false,
    required this.onComplete,
  });

  final String titre;
  final String? message;
  final bool erreur;

  /// Appelé quand les 4 chiffres sont saisis. Le clavier se vide ensuite.
  final Future<void> Function(String pin) onComplete;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _occupe = false;

  Future<void> _ajouter(String chiffre) async {
    if (_occupe || _pin.length >= PinService.longueur) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += chiffre);
    if (_pin.length == PinService.longueur) {
      _occupe = true;
      final saisi = _pin;
      await widget.onComplete(saisi);
      if (!mounted) return;
      setState(() {
        _pin = '';
        _occupe = false;
      });
    }
  }

  void _effacer() {
    if (_occupe || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final couleurErreur = cs.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.titre,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: Center(
            child: Text(
              widget.message ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: widget.erreur ? couleurErreur : cs.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(PinService.longueur, (i) {
            final plein = i < _pin.length;
            return Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: plein
                    ? (widget.erreur ? couleurErreur : cs.primary)
                    : Colors.transparent,
                border: Border.all(
                    color: widget.erreur ? couleurErreur : cs.primary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),
        for (final ligne in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final c in ligne) _touche(c)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 84),
              _touche('0'),
              SizedBox(
                width: 84,
                height: 64,
                child: IconButton(
                  onPressed: _effacer,
                  icon: const Icon(Icons.backspace_outlined),
                  tooltip: 'Effacer',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _touche(String c) {
    return SizedBox(
      width: 84,
      height: 64,
      child: TextButton(
        onPressed: () => _ajouter(c),
        style: TextButton.styleFrom(
          shape: const CircleBorder(),
          textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
        ),
        child: Text(c),
      ),
    );
  }
}
