FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg jq \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

ARG DOCKER_GID=988
RUN groupadd -g ${DOCKER_GID} docker || groupmod -g ${DOCKER_GID} docker || true \
 && usermod -aG docker jenkins

USER jenkins

ENV JENKINS_OPTS="--httpPort=8080"
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=180s \
  CMD curl -fsS http://localhost:8080/login || exit 1
