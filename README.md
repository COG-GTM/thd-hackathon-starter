# hackathon-starter
create-react-app + expressjs + mongodb + docker-compose!!

[![Node.JS Version](https://img.shields.io/badge/node.js-12.4.0-00ADD8.svg?style=flat)](https://nodejs.org/en/) 
[![Code Coverage](https://img.shields.io/codecov/c/github/homedepot/hackathon-starter.svg?style=flat)](https://codecov.io/gh/homedepot/hackathon-starter)
[![Build Status](https://travis-ci.org/homedepot/hackathon-starter.svg?branch=master)](https://travis-ci.org/homedepot/hackathon-starter)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat)](LICENSE)

## Quick Setup

This starter application uses docker-compose to get the entire environment setup off of the ground.

The tech stack is: 

- [create-react-app](https://github.com/facebook/create-react-app) on the front-end

- [express](https://expressjs.com/) API

- [Mongodb](https://www.mongodb.com/) for database 

If you don't have docker installed, install [docker desktop](https://www.docker.com/products/docker-desktop). 

From there, clone the repository into your workspace of choice. 

Finally, run the following command from your favorite terminal: 

```
docker-compose down && docker-compose build && docker-compose up
```

*NOTE*: The first build will be slow due to docker world-building

This will host your front end on `localhost:3001`, your api endpoint on `localhost:3002`, and mongodb will be networked internally (more details TBD).

To debug the api, start the inspector on loopback inside the container and forward it over `docker exec` rather than
publishing the port (the inspector allows arbitrary code execution to anyone who can reach it, so never bind it to
`0.0.0.0` or expose it in `docker-compose.yml`):

```
docker-compose exec api node --inspect=127.0.0.1:9229 src/app.js
```

Then attach your debugger from inside the container (e.g. `docker-compose exec api node inspect 127.0.0.1:9229`), or
forward the port over an SSH tunnel if you need to attach from another machine.

The frontend and backend will auto-refresh as you make changes, and the only time you will ever need to re-run `docker-compose down && docker-compose build && docker-compose up` 
is if you made changes to the package.json file in either ui or api.
 

## TODOs

- Add captcha: https://github.com/appleboy/react-recaptcha
