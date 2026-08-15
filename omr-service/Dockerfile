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
        python3 \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra \
        tesseract-ocr-deu tesseract-ocr-ita \
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
COPY server.py /app/server.py
# -u unbuffered, faulthandler: if python ever dies silently, get a stack
CMD ["python3", "-u", "-X", "faulthandler", "/app/server.py"]
