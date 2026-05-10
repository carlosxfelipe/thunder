# Thunar

Gerenciador de arquivos para macOS escrito em Swift com SwiftUI.

## Funcionalidades

- Navegação com abas
- Modo lista e modo ícones
- Copiar, recortar, colar e comprimir
- Quick Look (barra de espaço)
- Etiquetas coloridas (compatível com Finder)
- Mostrar/ocultar arquivos ocultos
- Abrir no Terminal

## Requisitos

- macOS 14.0 (Sonoma) ou superior
- Xcode 15 ou superior

## Como rodar

```
git clone https://github.com/carlosxfelipe/thunar.git
cd thunar
open thunar.xcodeproj
```

No Xcode, selecione o target `thunar` e clique em Run (Cmd+R).

## Build de distribuição (.dmg)

Para gerar um instalador no estilo "arraste para a pasta Aplicativos":

```
./scripts/build-dmg.sh
```

O arquivo `Thunar.dmg` será criado na raiz do projeto.

> **Aviso de Gatekeeper**: como o app não é assinado com Apple Developer ID, ao abrir pela primeira vez o macOS pode exibir *"Thunar não pôde ser aberto porque o desenvolvedor não pode ser verificado"* ou *"Thunar está danificado"*. Para contornar, escolha uma das opções abaixo.

### Opção A — Botão direito (recomendado)

1. Arraste o `Thunar.app` para `/Aplicativos`.
2. Clique com o **botão direito** sobre o app → **Abrir**.
3. No diálogo, clique em **Abrir** novamente.

A partir daí o macOS lembra a permissão.

### Opção B — Remover o atributo de quarentena pelo Terminal

Se aparecer "está danificado", rode:

```
xattr -cr /Applications/Thunar.app
```

Depois é só abrir normalmente.

## Atalhos de teclado

| Atalho | Ação |
|---|---|
| Cmd+C | Copiar |
| Cmd+X | Recortar |
| Cmd+V | Colar |
| Cmd+T | Nova aba |
| Cmd+W | Fechar aba |
| Ctrl+Tab | Próxima aba |
| Ctrl+Shift+Tab | Aba anterior |
| Space | Quick Look |
| Enter | Abrir item (modo ícones) |
| Setas | Navegar entre itens (modo ícones) |
| Shift+Setas | Seleção múltipla (modo ícones) |
| Shift+Clique | Seleção em bloco (modo ícones) |
| Cmd+Clique | Seleção individual |
| Cmd+Shift+. | Mostrar/ocultar arquivos ocultos |
| Letras/Números | Saltar para item pelo nome |
