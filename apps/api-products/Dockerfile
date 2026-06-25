FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

ENV PORT=3003
EXPOSE 3003

# ✅ user non-root avec UID numérique
RUN addgroup -g 1001 app && adduser -D -u 1001 -G app app
USER 1001

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3002/health || exit 1

CMD ["node", "src/index.js"]