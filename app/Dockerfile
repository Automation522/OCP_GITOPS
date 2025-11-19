FROM harbor.skyr.dca.scc/gitops/nodejs-18:latest AS base
WORKDIR /opt/app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

ENV PORT=8080
EXPOSE 8080

CMD ["npm", "start"]
