# ---- Building container ----

FROM node:latest as builder

# Build requirements
RUN apt-get update \
    && apt-get install -y \ 
    # build tools
    make gcc git \
    # build requirements for h2load
    g++ make binutils autoconf automake autotools-dev libtool pkg-config \
    zlib1g-dev libcunit1-dev libssl-dev libxml2-dev libev-dev libevent-dev libjansson-dev \
    libc-ares-dev libjemalloc-dev libsystemd-dev \
    cython3 python3-dev python-setuptools

# Install rust/crate and go
# https://go.dev/doc/install
# https://github.com/liuchong/docker-rustup/blob/master/dockerfiles/stable/Dockerfile
RUN curl -L -o go1.18.linux-amd64.tar.gz https://go.dev/dl/go1.18.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.18.linux-amd64.tar.gz \
    && curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain stable -y

ENV PATH=$PATH:/root/.cargo/bin:/usr/local/go/bin

# WRK https://github.com/wg/wrk
RUN git clone https://github.com/wg/wrk.git \
    && cd wrk \
    && make

# h2load https://github.com/nghttp2/nghttp2
# These are laid out this way (multiple apt-get installs) because this builds
# with HTTP/3 support. 
RUN git clone --depth 1 -b OpenSSL_1_1_1n+quic https://github.com/quictls/openssl \
    && cd openssl \
    && ./config --prefix=$PWD/build --openssldir=/etc/ssl \
    && make -j$(nproc) \
    && make install_sw

RUN git clone --depth 1 -b v0.2.0 https://github.com/ngtcp2/nghttp3 \
    && cd nghttp3 \
    && autoreconf -i \
    && ./configure --prefix=$PWD/build --enable-lib-only \
    && make -j$(nproc) \
    && make install

RUN git clone --depth 1 -b v0.2.1 https://github.com/ngtcp2/ngtcp2 \
    && cd ngtcp2 \
    && autoreconf -i \
    && ./configure --prefix=$PWD/build --enable-lib-only \
        PKG_CONFIG_PATH="$PWD/../openssl/build/lib/pkgconfig" \
    && make -j$(nproc) \
    && make install 

RUN apt-get install -y libelf-dev \
   && git clone --depth 1 -b v0.7.0 https://github.com/libbpf/libbpf \
   && cd libbpf \
   && PREFIX=$PWD/build make -C src install

RUN apt-get install -y python3-dev ruby clang-11 \
    && git clone https://github.com/nghttp2/nghttp2.git \
    && cd nghttp2 \
    && git submodule update --init \
    && autoreconf -i \
    && automake \
    && autoconf \
    && ./configure --with-mruby --with-neverbleed --enable-http3 --with-libbpf \
      --disable-python-bindings \
      CC=clang-11 CXX=clang++-11 \
      PKG_CONFIG_PATH="$PWD/../openssl/build/lib/pkgconfig:$PWD/../nghttp3/build/lib/pkgconfig:$PWD/../ngtcp2/build/lib/pkgconfig:$PWD/../libbpf/build/lib64/pkgconfig" \
      LDFLAGS="$LDFLAGS -Wl,-rpath,$PWD/../openssl/build/lib -Wl,-rpath,$PWD/../libbpf/build/lib64" \
    && make

# SlowHTTPTest https://github.com/shekyan/slowhttptest
RUN git clone https://github.com/shekyan/slowhttptest.git \
    && cd slowhttptest \
    && ./configure \
    && make

# Siege https://github.com/JoeDog/siege
RUN git clone https://github.com/JoeDog/siege.git \ 
    && cd siege \
    && utils/bootstrap \
    && ./configure --with-ssl \
    && make \
    && make install

# -- Rust packages -- 

# Drill https://github.com/fcsonline/drill
RUN cargo install drill

# -- Golang packages -- 

# Bombardier https://github.com/codesenberg/bombardier
RUN go install github.com/codesenberg/bombardier@latest

# Ali https://github.com/nakabonne/ali
RUN go install github.com/nakabonne/ali@latest

# Ddosify https://github.com/ddosify/ddosify
RUN go install go.ddosify.com/ddosify@latest

# Fortio https://github.com/fortio/fortio
RUN go install fortio.org/fortio@latest

# Vegeta https://github.com/tsenart/vegeta
RUN go install github.com/tsenart/vegeta@latest

# Tsung https://github.com/processone/tsung
RUN apt-get update \
    && apt-get install -y erlang \
    && git clone https://github.com/processone/tsung.git \
    && cd tsung \
    && ./configure \
    && make \
    && make install

# ---- Tool/target container ----

FROM node:latest as tools

# AutoCannon https://github.com/mcollina/autocannon
RUN npm install -g autocannon

# Node Clinic https://github.com/clinicjs/node-clinic
RUN npm install -g clinic

# K6 https://github.com/grafana/k6
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 \
    && echo "deb https://dl.k6.io/deb stable main" | tee /etc/apt/sources.list.d/k6.list \
    && apt-get update \
    && apt-get install k6

# -- Java packages --
# JMeter https://jmeter.apache.org
RUN apt-get install -y default-jre-headless unzip \
    && curl -L -o apache-jmeter-5.4.3.zip https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.4.3.zip \
    && unzip apache-jmeter-5.4.3.zip -d /usr/local/bin \
    && ln -s /usr/local/bin/apache-jmeter-5.4.3/bin/jmeter /usr/local/bin/jmeter \
    && rm -rf apache-jmeter-5.4.3.zip;

# Gatling https://gatling.io/open-source/
RUN curl -L -o gatling-charts-highcharts-bundle-3.7.6-bundle.zip https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/3.7.6/gatling-charts-highcharts-bundle-3.7.6-bundle.zip \
    && unzip gatling-charts-highcharts-bundle-3.7.6-bundle.zip -d /opt \
    && rm -rf gatling-charts-highcharts-bundle-3.7.6-bundle.zip

ENV GATLING_HOME="/opt/gatling-charts-highcharts-bundle-3.7.6"
ENV $PATH=$PATH:$GATLING_HOME

# Drill https://github.com/fcsonline/drill
COPY --from=builder /root/.cargo/bin/drill /usr/local/bin/drill

# Cassowary https://github.com/rogerwelin/cassowary
RUN mkdir cassowary \
    && cd cassowary \
    && curl -L -o cassowary_Linux_x86_64.tar.gz https://github.com/rogerwelin/cassowary/releases/download/v0.14.0/cassowary_Linux_x86_64.tar.gz \
    && tar -xzf cassowary_Linux_x86_64.tar.gz \
    && rm -rf cassowary_Linux_x86_64.tar.gz \
    && cp cassowary /usr/local/bin \
    && cd .. \
    && rm -rf cassowary

# WRK https://github.com/wg/wrk
COPY --from=builder /wrk/wrk /usr/local/bin/wrk

# h2load https://github.com/nghttp2/nghttp2
RUN apt-get update \
    && apt-get install -y zlib1g libcunit1 libssl1.1 libxml2 libev4 libjansson4 libc-ares2 libjemalloc2 libsystemd0
COPY --from=builder /nghttp2/src/.libs/* /usr/local/bin/
COPY --from=builder /openssl/build/lib/* /usr/local/lib/
COPY --from=builder /nghttp3/build/lib/* /usr/local/lib/
COPY --from=builder /ngtcp2/build/lib/* /usr/local/lib/
COPY --from=builder /libbpf/build/lib64/* /usr/local/lib64/

# RUN go get -u golang.org/x/net/http2 \
#     && go get -u golang.org/x/net/websocket \
#     && go get -u github.com/tatsuhiro-t/go-nghttp2

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/nghttp.conf \
    && echo "/usr/local/lib64" >> /etc/ld.so.conf.d/nghttp.conf \
    && ldconfig

# SlowHTTPTest https://github.com/shekyan/slowhttptest
COPY --from=builder /slowhttptest/src/slowhttptest /usr/local/bin/slowhttptest

# Siege https://github.com/JoeDog/siege
COPY --from=builder /usr/local/bin/siege /usr/local/bin/siege
COPY --from=builder /usr/local/bin/bombardment /usr/local/bin/bombardment
COPY --from=builder /usr/local/bin/siege2csv.pl /usr/local/bin/siege2csv.pl
COPY --from=builder /usr/local/bin/siege.config /usr/local/bin/siege.config

# Bombardier https://github.com/codesenberg/bombardier
# Ali https://github.com/nakabonne/ali
# Ddosify https://github.com/ddosify/ddosify
# Fortio https://github.com/fortio/fortio
# Vegeta https://github.com/tsenart/vegeta
COPY --from=builder /root/go/bin/bombardier /usr/local/bin/bombardier
COPY --from=builder /root/go/bin/ali /usr/local/bin/ali
COPY --from=builder /root/go/bin/ddosify /usr/local/bin/ddosify
COPY --from=builder /root/go/bin/fortio /usr/local/bin/fortio
COPY --from=builder /root/go/bin/vegeta /usr/local/bin/vegeta

# Goad https://github.com/goadapp/goad
RUN curl -L -o goad-linux-x86-64.zip https://github.com/goadapp/goad/releases/download/2.0.4/goad-linux-x86-64.zip \
    && unzip goad-linux-x86-64.zip -d /usr/local/bin \
    && rm -rf goad-linux-x86-64.zip

# Hey https://github.com/rakyll/hey
RUN curl -L -o /usr/local/bin/hey https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 \
    && chmod +x /usr/local/bin/hey

# Tsung https://github.com/processone/tsung
COPY --from=builder /usr/bin/tsung /usr/bin/tsung
COPY --from=builder /usr/lib/tsung /usr/lib/tsung
COPY --from=builder /usr/share/tsung /usr/share/tsung

# Nano
RUN apt-get install -y nano

# Clean apt cache
RUN rm -rf /var/lib/apt/lists/*