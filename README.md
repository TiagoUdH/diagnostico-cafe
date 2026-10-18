# Diagnóstico Café (app Flutter)

App offline que classifica doenças em folhas de café com o modelo escolhido no TCC (**EfficientNetV2B0 × BRACOL**)
e mostra **por que** chegou ao diagnóstico:

| Método | Como é calculado no celular | Custo |
|---|---|---|
| **Grad-CAM** | Calculado dentro do próprio `.tflite` (derivada explícita da cabeça densa, ver `exportar_app.ipynb`), junto com a classificação, para todas as classes | 0 inferências extras |
| **Fidelidade do Grad-CAM** (Inserção/Remoção, Petsiuk et al. 2018) | Mesmo procedimento do `mobilenet.ipynb`: revela/apaga as células do Grad-CAM em ordem e mede a probabilidade | 100 inferências |
| **Oclusão** (Zeiler & Fergus 2014) | Cobre uma região 8×8 por vez com a foto borrada e mede a queda de probabilidade | 65 inferências |
| **LIME** (Ribeiro et al. 2016) | Superpixels SLIC + 300 perturbações + Ridge ponderada (mesmos parâmetros do `lime_image` dos notebooks) | 300 inferências |

A confiança exibida é **calibrada** (Temperature Scaling ajustado na validação). Abaixo do limiar de abstenção
(70% por padrão, em `config.json`), o app avisa que o diagnóstico é incerto e pede outra foto.

Integrated Gradients não foi incluído: precisa de gradientes através de todo o backbone, que o TFLite não calcula.

## 1. Gerar o modelo

1. No Kaggle, rode o `exportar_app.ipynb` (repositório do TCC: [TiagoUdH/tcc](https://github.com/TiagoUdH/tcc)) com o
   `.keras` do EfficientNetV2B0 × BRACOL anexado.
   Ele confere numericamente que o Grad-CAM exportado é igual ao do `mobilenet.ipynb` e mede a acurácia do
   `.tflite` quantizado no teste.
2. Baixe `app_assets.zip` e extraia `modelo.tflite` e `config.json` em `assets/modelo/`.

O modelo atual já está em `assets/modelo/` (acurácia 96,8% e F1-Macro 0,966 no teste do BRACOL, `.tflite` quantizado).

## 2. Rodar o app

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) 3.24+ e Android Studio (SDK Android) ou Xcode.

```bash
flutter pub get
flutter run
```

Para gerar o APK de instalação: `flutter build apk --release` (o arquivo fica em
`build/app/outputs/flutter-apk/app-release.apk`).

Testes das partes de IA em Dart (regressão do LIME e borrão conferidos contra scikit-learn e OpenCV):

```bash
flutter test
```

## Estrutura

```
lib/
  main.dart                  carrega o modelo e abre a tela inicial
  ia/
    config_modelo.dart       lê assets/modelo/config.json
    executor_modelo.dart     interpretador TFLite (entrada 224×224×3, saídas logits + Grad-CAM)
    imagem.dart              decodificação, EXIF, redimensionamento e borrão gaussiano
    explicacoes.dart         Oclusão, Inserção/Remoção e LIME
    slic.dart                superpixels SLIC
    matematica.dart          softmax, AUC e Ridge ponderada
    visualizacao.dart        mapas de calor (jet) e desenho do LIME
    motor_ia.dart            roda tudo em isolates (a interface não trava)
  telas/                     tela inicial e de resultado
  widgets/                   gráfico das curvas de Inserção/Remoção
```
