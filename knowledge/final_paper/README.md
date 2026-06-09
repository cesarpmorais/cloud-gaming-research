# TCC — Texto Final

LaTeX (IEEEtran) em português. Um arquivo por capítulo, incluídos via `\input` em `main.tex`.

## Estrutura

- `main.tex` — preâmbulo, título, abstract, includes
- `01-introducao.tex` — Introdução
- `02-referencial.tex` — Referencial Teórico
- `03-contribuicao.tex` — Contribuição
- `04-metodologia.tex` — Metodologia
- `05-resultados.tex` — Resultados
- `06-conclusao.tex` — Conclusão
- `bibliography.bib` — BibTeX

Os capítulos estão **scaffoldados como comentários em forma de "beats"** — cada subseção lista o que precisa entrar nela. Preenchemos um capítulo de cada vez, alinhando o storytelling antes de redigir.

## Compilação

```
pdflatex main && bibtex main && pdflatex main && pdflatex main
```

## Fluxo de escrita

1. Acordar a tese de uma frase do capítulo
2. Acordar os 3–5 beats que precisam entrar
3. Identificar as fontes (arquivos de `knowledge/`) que alimentam cada beat
4. Redigir em LaTeX
5. Revisar
