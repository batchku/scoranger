# Audiveris OMR as a tiny HTTP service (Cloud Run).
# POST a PDF, get back MusicXML (.mxl) — same pipeline as the desktop:
#   Audiveris -batch -export -output <dir> <pdf>

FROM eclipse-temurin:21-jdk AS build
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
ARG AUDIVERIS_REF=5.11.0
RUN git clone --depth 1 --branch ${AUDIVERIS_REF} https://github.com/audiveris/audiveris /src
WORKDIR /src
RUN ./gradlew --no-daemon distTar \
 && mkdir /opt/audiveris \
 && tar -xf $(find . -path "*/build/distributions/*.tar" | head -1) \
        -C /opt/audiveris --strip-components=1

FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra \
        tesseract-ocr-deu tesseract-ocr-ita \
        fontconfig fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/audiveris /opt/audiveris
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata \
    AUDIVERIS_BIN=/opt/audiveris/bin/Audiveris \
    PORT=8080
COPY server.py /app/server.py
CMD ["python3", "/app/server.py"]
