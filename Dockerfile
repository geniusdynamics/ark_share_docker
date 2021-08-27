# Share build

FROM 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_base:latest

LABEL ORG="Armedia LLC" \
      APP="Share" \
      VERSION="1.0" \
      IMAGE_SOURCE=https://github.com/ArkCase/ark_share \
      MAINTAINER="Armedia LLC"

#################
# Build JDK
#################

ARG JAVA_VERSION="11.0.12.0.7-0.el7_9"

ENV JAVA_HOME=/usr/lib/jvm/java \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN yum update -y && \
    yum -y install java-11-openjdk-devel-${JAVA_VERSION} unzip && \
    $JAVA_HOME/bin/javac -version

#################
# Build Tomcat
#################

ARG TOMCAT_VERSION="9.0.50"
ARG TOMCAT_MAJOR_VERSION="9"
ARG TOMCAT="apache-tomcat-${TOMCAT_VERSION}"
ARG TOMCAT_TARBALL="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ARG TOMCAT_TARBALL_SHA512="06cd51abbeebba9385f594ed092bd30e510b6314c90c421f4be5d8bec596c6a177785efc2ce27363813f6822af89fc88a2072d7b051960e5387130faf69c447b"
ARG TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-${TOMCAT_MAJOR_VERSION}/v${TOMCAT_VERSION}/bin/${TOMCAT_TARBALL}"

ENV CATALINA_HOME /usr/local/tomcat
ENV CATALINA_PID="${CATALINA_HOME}/temp/tomcat.pid" \
    PATH=${CATALINA_HOME}/bin:${PATH}
WORKDIR ${CATALINA_HOME}

ADD "${TOMCAT_URL}" ./

RUN set -eux; \
    checksum=$(sha512sum "$TOMCAT_TARBALL" | awk '{ print $1 }');  \
        if [ $checksum != $TOMCAT_TARBALL_SHA512 ]; then \
            echo "Unexpected SHA512 checkum for Tomcat tarball; possible man-in-the-middle attack"; \
            exit 1; \
        fi; \
    # use strip components to deploy all children into the tomcat directory
    tar -xvf "$TOMCAT_TARBALL" --strip-components=1; \
    rm "$TOMCAT_TARBALL"; \
    chmod u+x bin/*.sh; \
    # sh removes env vars it doesn't support (ones with periods)
    # https://github.com/docker-library/tomcat/issues/77
    find ./bin/ -name '*.sh' -exec sed -ri 's|^#!/bin/sh$|#!/usr/bin/env bash|' '{}' +; \
    # fix permissions (especially for running as non-root)
    # https://github.com/docker-library/tomcat/issues/35
    chmod -R +rX . ; \
    chmod 777 logs work ; \
    # Security improvements:
    # Remove server banner, Turn off loggin by the VersionLoggerListener, enable remoteIP valve so we know who we're talking to
    sed -i \
    -e "s/\  <Listener\ className=\"org.apache.catalina.startup.VersionLoggerListener\"/\  <Listener\ className=\"org.apache.catalina.startup.VersionLoggerListener\"\ logArgs=\"false\"/g" \
    -e "s%\(^\s*</Host>\)%\t<Valve className=\"org.apache.catalina.valves.RemoteIpValve\" />\n\n\1%" \
    -e "s/\    <Connector\ port=\"8080\"\ protocol=\"HTTP\/1.1\"/\    <Connector\ port=\"8080\"\ protocol=\"HTTP\/1.1\"\n\               Server=\" \"/g" ./conf/server.xml; \
    # Removal of default/unwanted Applications
    rm -rf ./webapps/* ./temp/* ./logs/* ./bin/*.bat; \
    # Replace default 404,403,500 page
    sed -i "$ d" ./conf/web.xml ; \
    sed -i -e "\$a\    <error-page\>\n\        <error-code\>404<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\    <error-page\>\n\        <error-code\>403<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\    <error-page\>\n\        <error-code\>500<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\n\<\/web-app\>" ./conf/web.xml 

#################
# Build Share
#################

# Set default docker_context.
ARG resource_path=artifacts

# Set default user information
ARG GROUPNAME=Alfresco
ARG GROUPID=1000
ARG IMAGEUSERNAME=alfresco
ARG USERID=33000

# Set default environment args
ARG TOMCAT_DIR=/usr/local/tomcat

# Set Versions
ARG ALFRESCO_VERSION="7.0.0"
ARG ALFRESCO_AGS_VERSION="3.5.a"
ARG ALFRESCO_GOOGLEDRIVE_VERSION="3.2.1.3"

# Variables: Software download stuff
ARG ALFRESCO="alfresco-content-services-community-distribution-${ALFRESCO_VERSION}"
ARG ALFRESCO_ZIP=${ALFRESCO}.zip
ARG ALFRESCO_URL="https://artifacts.alfresco.com/nexus/content/repositories/releases/org/alfresco/alfresco-content-services-community-distribution/${ALFRESCO_VERSION}/${ALFRESCO_ZIP}"
ARG ALFRESCO_ZIP_SHA1="f25f5550e04698b5c55224bdcf739bcff03f0773"
ARG SHARE_AGS="alfresco-governance-services-community-share-${ALFRESCO_AGS_VERSION}"
ARG SHARE_AGS_AMP=${SHARE_AGS}.amp
ARG SHARE_AGS_URL="https://artifacts.alfresco.com/nexus/content/repositories/releases/org/alfresco/alfresco-governance-services-community-share/${ALFRESCO_AGS_VERSION}/${SHARE_AGS_AMP}"
ARG SHARE_AGS_AMP_SHA1="eb3f4a9290c711cebb2e3a624ed3089a5cca8730"
ARG SHARE_GOOGLEDRIVE="alfresco-googledrive-share-${ALFRESCO_GOOGLEDRIVE_VERSION}"
ARG SHARE_GOOGLEDRIVE_AMP=${SHARE_GOOGLEDRIVE}.amp
ARG SHARE_GOOGLEDRIVE_URL="https://artifacts.alfresco.com/nexus/content/repositories/releases/org/alfresco/integrations/alfresco-googledrive-share/${ALFRESCO_GOOGLEDRIVE_VERSION}/${SHARE_GOOGLEDRIVE_AMP}"
ARG SHARE_GOOGLEDRIVE_AMP_SHA1="f466b0cda9f682f7880030e10604dbfc0b1f42fe"

# Set Working dir
WORKDIR ${TOMCAT_DIR}

ADD "${ALFRESCO_URL}" "${SHARE_AGS_URL}" "${SHARE_GOOGLEDRIVE_URL}" /tmp/

# Create prerequisite to store tools and properties
# Create required directories
# unzip distribution
# Copy the share WAR file to the appropriate location for your application server
# Copy the alfresco-mmt.jar
# Copy Licenses to the root of the Docker image
RUN set -eux; \
    checksum=$(sha1sum "/tmp/${ALFRESCO_ZIP}" | awk '{ print $1 }');  \
        if [ $checksum != ${ALFRESCO_ZIP_SHA1} ]; then \
            echo "Unexpected SHA1 checkum for Alfresco zip; possible man-in-the-middle attack"; \
            exit 1; \
        fi; \
    checksum=$(sha1sum "/tmp/${SHARE_AGS_AMP}" | awk '{ print $1 }');  \
        if [ $checksum != ${SHARE_AGS_AMP_SHA1} ]; then \
            echo "Unexpected SHA1 checkum for AGS amp; possible man-in-the-middle attack"; \
            exit 1; \
        fi; \
    checksum=$(sha1sum "/tmp/${SHARE_GOOGLEDRIVE_AMP}" | awk '{ print $1 }');  \
        if [ $checksum != ${SHARE_GOOGLEDRIVE_AMP_SHA1} ]; then \
            echo "Unexpected SHA1 checkum for Googledrive amp; possible man-in-the-middle attack"; \
            exit 1; \
        fi; \
    mkdir -p shared/classes/alfresco/web-extension ; \
    mkdir -p amps_share ; \
    mkdir alfresco-mmt ; \
    unzip -d /tmp/${ALFRESCO} /tmp/${ALFRESCO_ZIP} ; \
    mv /tmp/${ALFRESCO}/licenses /. ; \
    mv /tmp/${ALFRESCO}/bin/alfresco-mmt.jar alfresco-mmt/ ; \
    mv /tmp/${SHARE_AGS_AMP} amps_share/. ; \
    mv /tmp/${SHARE_GOOGLEDRIVE_AMP} amps_share/. ; \
    mv /tmp/${ALFRESCO}/web-server/shared/classes/alfresco/web-extension/* shared/classes/alfresco/web-extension/. ; \
    unzip -d webapps/share /tmp/${ALFRESCO}/web-server/webapps/share.war ; \
    yum -y erase unzip; \
    yum clean all; \
    rm -rf /tmp/*

# Copy the updated log configs to remove any logging to a file and only to stdout (console)
COPY ${resource_path}/substituter.sh shared/classes/alfresco
COPY ${resource_path}/log4j.properties webapps/share/WEB-INF/classes/log4j.properties
COPY ${resource_path}/logging.properties conf/logging.properties

# install amps on share webapp
RUN java -jar ${TOMCAT_DIR}/alfresco-mmt/alfresco-mmt*.jar list $TOMCAT_DIR/webapps/share && \
    java -jar ${TOMCAT_DIR}/alfresco-mmt/alfresco-mmt*.jar install \
              ${TOMCAT_DIR}/amps_share \
              ${TOMCAT_DIR}/webapps/share -directory -nobackup -force && \
    java -jar ${TOMCAT_DIR}/alfresco-mmt/alfresco-mmt*.jar list $TOMCAT_DIR/webapps/share && \
# The standard configuration is to have all Tomcat files owned by root with group GROUPNAME and whilst owner has read/write privileges, 
# group only has restricted permissions and world has no permissions.
    mkdir -p ${TOMCAT_DIR}/conf/Catalina/localhost && \
    groupadd -g ${GROUPID} ${GROUPNAME} && \
    useradd -u ${USERID} -G ${GROUPNAME} ${IMAGEUSERNAME} && \
    chgrp -R ${GROUPNAME} ${TOMCAT_DIR} && \
    chmod g+rx ${TOMCAT_DIR}/conf && \
    chmod -R g+rwx ${TOMCAT_DIR}/shared && \
    chmod -R g+r ${TOMCAT_DIR}/conf && \
    find ${TOMCAT_DIR}/webapps -type d -exec chmod 0750 {} \; && \
    find ${TOMCAT_DIR}/webapps -type f -exec chmod 0640 {} \; && \
    chmod -R g+r ${TOMCAT_DIR}/webapps && \
    chmod g+r ${TOMCAT_DIR}/conf/Catalina && \
    chmod g+r ${TOMCAT_DIR}/amps_share/* && \
    chmod g+rwx,o-w ${TOMCAT_DIR}/logs && \
    chmod g+rwx ${TOMCAT_DIR}/temp && \
    chmod g+rwx,o-w ${TOMCAT_DIR}/work && \
    chmod 664 ${TOMCAT_DIR}/alfresco-mmt/alfresco-mmt.jar && \
    find /licenses -type d -exec chmod 0755 {} \; && \
    find /licenses -type f -exec chmod 0644 {} \;

USER ${IMAGEUSERNAME}

ENTRYPOINT ["/usr/local/tomcat/shared/classes/alfresco/substituter.sh", "catalina.sh run"]

EXPOSE 8080
