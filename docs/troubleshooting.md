# Ce qui a cassé et comment je l'ai réparé

Journal des vraies pannes rencontrées. Format : symptôme → cause → réparation → leçon.
C'est la section la plus lue en entretien : remplir au fil de l'eau, avec les messages d'erreur exacts.

## Projet 1 — CI/CD

### 1. <titre court de la panne>
- **Symptôme :** <message d'erreur exact, étape du pipeline>
- **Cause :** <ce qui se passait réellement>
- **Réparation :** <commit / changement appliqué>
- **Leçon :** <ce que je fais différemment maintenant>

<!-- Pannes classiques à provoquer volontairement pour s'entraîner :
- retirer le bloc `permissions: packages: write` -> push GHCR refusé (denied: permission_denied)
- lancer uvicorn avec --host 127.0.0.1 -> conteneur "healthy" impossible à joindre depuis l'hôte
- remplacer python:3.12-slim par python:3.12 -> taille de l'image x5
- casser un test dans une PR -> merge bloqué par la protection de branche
-->
