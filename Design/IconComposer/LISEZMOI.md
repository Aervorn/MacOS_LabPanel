# Calques pour Icon Composer

Calques de l'icône de LabPanel pour Icon Composer (macOS 26), générés par `make_layers.py`.
Tous sur le même canevas de 1024 × 1024, à pleine taille : ils se superposent sans réglage.
L'icône elle-même est `LabPanel/AppIcon.icon` (à ouvrir dans Icon Composer pour l'ajuster).

| Fichier | Contenu | Dans l'icône |
|---|---|---|
| `1-fond.svg` | Dégradé indigo → bleu → cyan | Référence : l'icône utilise le dégradé de fond d'Icon Composer (#312E81 → #06B6D4) |
| `2-fenetre.svg` | Fenêtre claire et filet sous les onglets | Groupe « Fenêtre » |
| `3-onglets.svg` | Trois onglets, celui du milieu ouvert | Groupe « Fenêtre », au-dessus |
| `4-serveurs.svg` | Baie de trois serveurs | Groupe « Serveurs » |
| `5-voyants.svg` | Voyants des serveurs | Groupe « Serveurs », au-dessus |

Pas de coins arrondis, d'ombre ni de reflet : macOS les ajoute lui-même, et adapte l'icône
aux styles clair, sombre, transparent et teinté.
