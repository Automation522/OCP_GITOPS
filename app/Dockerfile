FROM harbor.skyr.dca.scc/gitops/nodejs-18:latest AS base

USER 0
WORKDIR /opt/app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .
RUN chown -R 1001:0 /opt/app

USER 1001
ENV PORT=8080
EXPOSE 8080

CMD ["npm", "start"]
