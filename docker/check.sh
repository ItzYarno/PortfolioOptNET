#!/bin/bash
# Kijkt je documenten na voordat je ze indient.
#
# Wordt aangeroepen vanuit check.sh (macOS, Linux, Git Bash) of check.bat
# (Windows). Het script beoordeelt je inhoud niet - het zoekt naar de dingen
# die elk jaar opnieuw vergeten worden.

set -o nounset

readonly project_root="${PROJECT_ROOT:-/project}"
cd "${project_root}"

fouten=0
waarschuwingen=0

# printf en niet echo: echo zet \b en \r in de tekst om naar stuurtekens, en de
# namen van LaTeX-commando's beginnen nu eenmaal met een backslash.
fout()          { printf '  FOUT         %s\n' "$*"; fouten=$((fouten + 1)); }
waarschuwing()  { printf '  LET OP       %s\n' "$*"; waarschuwingen=$((waarschuwingen + 1)); }
goed()          { printf '  in orde      %s\n' "$*"; }

echo
echo "=============================================================="
echo " Nazicht van je graduaatsproject"
echo "=============================================================="
echo
echo "1. Je projectgegevens"

controleer_gegeven() {
  # $1 = commandonaam, $2 = de standaardwaarde die vervangen moet zijn
  waarde=$(sed -n "s/^.*newcommand{.$1}{\(.*\)}.*$/\1/p" projectgegevens.tex | head -1)
  if [ -z "${waarde}" ]; then
    fout "\\$1 ontbreekt in projectgegevens.tex"
  elif [ "${waarde}" = "$2" ]; then
    fout "\\$1 staat nog op de standaardwaarde: ${waarde}"
  else
    goed "\\$1 = ${waarde}"
  fi
}

controleer_gegeven studentnaam   "Voornaam Familienaam"
controleer_gegeven studentemail  "voornaam.familienaam@student.hogent.be"
controleer_gegeven bestandsnaam  "Familienaam-Voornaam"
controleer_gegeven projecttitel  "De titel van je graduaatsproject"
controleer_gegeven bedrijfsnaam  "Naam van je stagebedrijf"
controleer_gegeven mentornaam    "Voornaam Familienaam"
controleer_gegeven repolink      "https://les.lucvervoort.org/jouwnaam/graduaatsproject"

echo
echo "2. Overgebleven sjabloontekst"

resten=$(grep -rl "Vervang deze tekst\|Vervang deze alinea\|Vervang deze afbeelding\|Replace this text" \
  gradproject voorstel poster 2>/dev/null | sort)
if [ -n "${resten}" ]; then
  for bestand in ${resten}; do
    aantal=$(grep -c "Vervang deze\|Replace this text" "${bestand}")
    fout "${bestand}: nog ${aantal} stuk(ken) sjabloontekst"
  done
else
  goed "geen sjabloontekst meer gevonden"
fi

echo
echo "3. Verplichte onderdelen van je rapport"

if grep -q "Vervang deze tekst door je Nederlandse samenvatting" gradproject/samenvatting.tex; then
  fout "de Nederlandse samenvatting is nog niet geschreven"
else
  goed "Nederlandse samenvatting aanwezig"
fi

if grep -q "Replace this text with the English version" gradproject/samenvatting.tex; then
  fout "de Engelse samenvatting is nog niet geschreven (verplicht)"
else
  goed "Engelse samenvatting aanwezig"
fi

if grep -q "Vervang deze alinea door een korte inleiding: heb je AI gebruikt" gradproject/ai-verantwoording.tex; then
  fout "de verantwoording van je AI-gebruik is nog niet ingevuld (verplicht, ook als je geen AI gebruikte)"
else
  goed "verantwoording van het AI-gebruik ingevuld"
fi

echo
echo "4. Bronnen"

verwijzingen=$(grep -rho "autocite{[^}]*}\|textcite{[^}]*}" gradproject/*.tex 2>/dev/null | wc -l)
if [ "${verwijzingen}" -eq 0 ]; then
  waarschuwing "je verwijst nergens naar een bron. Dat kan kloppen, maar bij een project met technologiekeuzes is het ongewoon."
else
  goed "${verwijzingen} bronverwijzing(en) in je tekst"
fi

if grep -q "Martin2008\|DockerDocs2026\|Fowler2018" gradproject/technologie.tex 2>/dev/null; then
  waarschuwing "de voorbeeldverwijzingen uit het sjabloon staan er nog in (technologie.tex)"
fi

echo
echo "5. Geheimen en persoonsgegevens"

verdacht=$(grep -rniE "(password|passwd|wachtwoord|api[_-]?key|secret|token)[[:space:]]*[=:][[:space:]]*['\"][^'\"]{6,}" \
  gradproject voorstel poster 2>/dev/null | head -5)
if [ -n "${verdacht}" ]; then
  waarschuwing "mogelijk een wachtwoord of sleutel in je tekst:"
  echo "${verdacht}" | sed 's/^/               /'
else
  goed "geen wachtwoorden of sleutels gevonden in de teksten"
fi

echo
echo "6. De PDF's"

for doc in rapport voorstel poster; do
  case "${doc}" in
    rapport) script="make_report" ;;
    *)       script="make_${doc}" ;;
  esac
  pdf=$(ls output/*"${doc}".pdf 2>/dev/null | head -1)
  if [ -z "${pdf}" ]; then
    waarschuwing "output/${doc}.pdf bestaat nog niet - bouw hem met ${script}"
  else
    bladzijden=$(grep -h "Output written on .*${doc}" "output/${doc}.log" 2>/dev/null |
                 sed -n 's/.*(\([0-9]*\) page.*/\1/p' | head -1)
    if [ "${doc}" = "rapport" ] && [ -n "${bladzijden}" ]; then
      if [ "${bladzijden}" -lt 12 ]; then
        waarschuwing "je rapport telt ${bladzijden} bladzijden - dat is aan de korte kant"
      elif [ "${bladzijden}" -gt 30 ]; then
        waarschuwing "je rapport telt ${bladzijden} bladzijden - de richtwaarde is 10 tot 15 bladzijden kerntekst"
      else
        goed "rapport: ${bladzijden} bladzijden"
      fi
    else
      goed "${doc}: ${pdf}"
    fi
  fi
done

echo
echo "7. Opmaak: steekt er iets buiten de kolom of de bladzijde?"

# LaTeX meldt een te brede regel of tabel enkel als 'Overfull \hbox' in het logboek;
# in de PDF wordt ze dan afgesneden of loopt ze in de andere kolom. Kleine overschrijdingen
# (een afgebroken woord, enkele punten) ziet niemand: pas vanaf drempel_pt melden we iets.
readonly drempel_pt=5
for doc in voorstel rapport poster; do
  log="output/${doc}.log"
  [ -f "${log}" ] || continue
  # awk volgt welk .tex-bestand LaTeX als laatste opende; dat is vermoedelijk de plaats van de fout.
  meldingen=$(awk -v drempel="${drempel_pt}" '
    { if (match($0, /\(\.?\/?[^ ()]*\.tex/)) { bestand = substr($0, RSTART + 1, RLENGTH - 1); sub(/^\.\//, "", bestand) } }
    /^Overfull \\hbox \([0-9.]+pt too wide\)/ {
      pt = $0; sub(/^Overfull \\hbox \(/, "", pt); sub(/pt too wide.*/, "", pt)
      regels = $0; sub(/.*at lines /, "", regels); sub(/--/, "-", regels)
      if (pt + 0 >= drempel) printf "%s|%.1f|%.1f|%s\n", bestand, pt, pt * 0.03515, regels
    }' "${log}")
  if [ -z "${meldingen}" ]; then
    goed "${doc}: niets steekt buiten de kolom"
  else
    echo "${meldingen}" | while IFS='|' read -r bestand pt cm regels; do
      printf '  LET OP       %s: iets steekt %s pt (%s cm) buiten de kolom, vermoedelijk in %s, regels %s.\n' \
        "${doc}" "${pt}" "${cm}" "${bestand:-?}" "${regels}"
    done
    aantal=$(echo "${meldingen}" | wc -l)
    waarschuwingen=$((waarschuwingen + aantal))
    echo "               Meestal een te brede tabel (gebruik tabularx, zie de planningstabel in het"
    echo "               voorstel) of een lange URL. In de PDF wordt dat afgesneden: kijk het na."
  fi
done

echo
echo "=============================================================="
if [ "${fouten}" -eq 0 ] && [ "${waarschuwingen}" -eq 0 ]; then
  echo " Alles in orde. Veel succes met je verdediging."
elif [ "${fouten}" -eq 0 ]; then
  echo " Geen fouten, ${waarschuwingen} punt(en) om even naar te kijken."
else
  echo " ${fouten} fout(en) en ${waarschuwingen} aandachtspunt(en)."
  echo " Los de fouten op voor je indient."
fi
echo "=============================================================="
echo

[ "${fouten}" -eq 0 ]
