# Audiveris OMR as a tiny HTTP service (Cloud Run).
# POST a PDF, get back MusicXML (.mxl) — same pipeline as the desktop:
#   Audiveris -batch -export -output <dir> <pdf>

FROM eclipse-temurin:25-jdk AS build
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
ARG AUDIVERIS_REF=5.11.0
RUN git clone --depth 1 --branch ${AUDIVERIS_REF} https://github.com/audiveris/audiveris /src
WORKDIR /src
RUN ./gradlew --no-daemon distTar \
 && mkdir /opt/audiveris \
 && tar -xf $(find . -path "*/build/distributions/*.tar" | head -1) \
        -C /opt/audiveris --strip-components=1

FROM eclipse-temurin:25-jre
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 curl \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra \
        libtesseract-dev libleptonica-dev \
        fontconfig fonts-dejavu-core \
    && (apt-get install -y --no-install-recommends libgtk-3-0t64 \
        || apt-get install -y --no-install-recommends libgtk-3-0) \
    && rm -rf /var/lib/apt/lists/*
# tess4j loads "tesseract" via JNA, which needs the unversioned .so name
ENV JNA_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
COPY --from=build /opt/audiveris /opt/audiveris
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata \
    AUDIVERIS_BIN=/opt/audiveris/bin/Audiveris \
    PORT=8080

# THE LANGUAGE DATA APT INSTALLS CANNOT BE USED BY AUDIVERIS, and this is why
# scans came back with no lyrics, no chord symbols, no title and no part names.
#
# A .traineddata file is a container of components. Debian and Ubuntu build
# tesseract-ocr-eng from tessdata_fast, which holds the LSTM model and nothing
# else; the legacy recogniser's components (inttemp, pffmtable, normproto) are
# absent. Audiveris 5.11 initialises Tesseract in LEGACY mode, so against that
# file it logs
#
#   Could not initialize TessBaseAPI languages: eng in legacy mode
#   ... No OCR'd lines
#
# and the TEXTS step yields nothing at all for the rest of the run. Measured
# on a 32-bar lead sheet: 0 chord symbols and 0 lyrics with the apt file, 28
# and 124 with the file below -- and the words it could not read came back as
# 19 dynamics, 50 articulations and 22 fermatas that are not on the page. It
# is not even slower: the same 12-page quartet took 157s with working OCR
# against 186s without, because misreading text as symbols costs more than
# reading it.
#
# So the two languages Audiveris may be asked for are taken from the tessdata
# repository, which carries both recognisers, pinned by tag and checked by
# digest. German and Italian are no longer installed at all: they were the
# unusable apt build, nothing in this service selects them (Audiveris's
# default language specification is "eng"), and 50MB of data no recogniser
# can load is worse than not offering the language.
ARG TESSDATA_REF=4.1.0
RUN set -eu; \
    for lang in eng fra; do \
        curl -fsSL -o "${TESSDATA_PREFIX}/${lang}.traineddata" \
        "https://github.com/tesseract-ocr/tessdata/raw/${TESSDATA_REF}/${lang}.traineddata"; \
    done; \
    echo "daa0c97d651c19fba3b25e81317cd697e9908c8208090c94c3905381c23fc047  ${TESSDATA_PREFIX}/eng.traineddata" > /tmp/tessdata.sha256; \
    echo "eac01c1d72540d6090facb7b2f42dd0a2ee8fc57c5be1b20548ae668e2761913  ${TESSDATA_PREFIX}/fra.traineddata" >> /tmp/tessdata.sha256; \
    sha256sum -c /tmp/tessdata.sha256; \
    rm /tmp/tessdata.sha256
# And the build FAILS if what landed cannot drive the legacy recogniser -- a
# digest proves the bytes arrived, not that they are the right kind of file,
# and the wrong kind fails silently at run time, on somebody's scan.
COPY verify_tessdata.py /app/verify_tessdata.py
RUN python3 /app/verify_tessdata.py \
        "${TESSDATA_PREFIX}/eng.traineddata" \
        "${TESSDATA_PREFIX}/fra.traineddata"
COPY requirements.txt /app/requirements.txt
# --break-system-packages: the runtime image's python is the system one and
# there is no venv here by design. One dependency, pinned.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    -r /app/requirements.txt
COPY identity.py /app/identity.py
COPY server.py /app/server.py
# -u unbuffered, faulthandler: if python ever dies silently, get a stack
CMD ["python3", "-u", "-X", "faulthandler", "/app/server.py"]
