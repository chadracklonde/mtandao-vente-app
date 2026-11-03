import 'package:flutter/material.dart';

/// Fenêtre avec un seul champ de texte. Le champ appartient à la fenêtre, qui
/// le libère elle-même une fois fermée (le libérer plus tôt provoque une erreur
/// pendant l'animation de fermeture).
/// Retourne le texte saisi (sans espaces autour), ou null si annulé.
Future<String?> demanderTexte(
  BuildContext context, {
  required String titre,
  required String libelle,
  String initial = '',
  String? aide,
  TextInputType? clavier,
  TextCapitalization majuscules = TextCapitalization.none,
  bool masquer = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogueTexte(
      titre: titre,
      libelle: libelle,
      initial: initial,
      aide: aide,
      clavier: clavier,
      majuscules: majuscules,
      masquer: masquer,
    ),
  );
}

class _DialogueTexte extends StatefulWidget {
  const _DialogueTexte({
    required this.titre,
    required this.libelle,
    required this.initial,
    required this.aide,
    required this.clavier,
    required this.majuscules,
    required this.masquer,
  });
  final String titre;
  final String libelle;
  final String initial;
  final String? aide;
  final TextInputType? clavier;
  final TextCapitalization majuscules;
  final bool masquer;

  @override
  State<_DialogueTexte> createState() => _DialogueTexteState();
}

class _DialogueTexteState extends State<_DialogueTexte> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.aide != null) ...[
            Text(widget.aide!),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: widget.clavier,
            textCapitalization: widget.majuscules,
            obscureText: widget.masquer,
            enableSuggestions: !widget.masquer,
            autocorrect: !widget.masquer,
            decoration: InputDecoration(
                labelText: widget.libelle, border: const OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Fenêtre « Nouveau client » : nom et téléphone (facultatif).
/// Retourne (nom, téléphone ou null), ou null si annulé.
Future<(String, String?)?> demanderClient(BuildContext context) {
  return showDialog<(String, String?)>(
    context: context,
    builder: (_) => const _DialogueClient(),
  );
}

class _DialogueClient extends StatefulWidget {
  const _DialogueClient();

  @override
  State<_DialogueClient> createState() => _DialogueClientState();
}

class _DialogueClientState extends State<_DialogueClient> {
  final _nom = TextEditingController();
  final _tel = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    _tel.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    if (nom.isEmpty) return;
    final tel = _tel.text.trim();
    Navigator.pop(context, (nom, tel.isEmpty ? null : tel));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau client'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nom,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Nom', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Téléphone (facultatif)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _valider, child: const Text('Ajouter')),
      ],
    );
  }
}
