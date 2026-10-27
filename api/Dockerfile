FROM node:22-alpine

WORKDIR /api

ENV PATH /api/node_modules/.bin:$PATH

COPY package*.json ./

RUN yarn install --silent

COPY . .

USER node

EXPOSE 8080

CMD ["yarn", "start"]
