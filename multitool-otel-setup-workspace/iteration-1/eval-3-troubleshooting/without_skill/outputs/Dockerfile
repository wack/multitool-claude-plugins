FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
ARG APP_VERSION=unknown
ENV APP_VERSION=${APP_VERSION}
CMD ["node", "dist/index.js"]
