# pigeosolutions/hyfaa-postgis

This is a copy of the config from the [postgis/postgis](https://github.com/postgis/docker-postgis) config, excluding the tiger extension, which will be of no use for our use-case

It also initializes the DB (structure mostly) for the HYFAA-MGB data:
- publish geo data in a `geospatial` schema
- create tables and views for hyfaa data in a `hyfaa` data
- manage access to relevant tables to tileserv user

## Build the docker image
`make docker-build`

## Run the docker image
This is a PostGIS image, so the documentation from [PostGIS](https://hub.docker.com/r/postgis/postgis) 
and [PostgreSQL](https://hub.docker.com/_/postgres) apply.

There is an additional environment variable supported:
- **WITH_SAMPLE=yes**: loads sample data into the data_with_assim table, so that the derivated views are populated (namely 
`hyfaa.data_with_assim_aggregate_geo` that is expected to be used with tileserv, for the hyfaa frontend)

You can run this image alone with
```
docker run -it --rm --name pg  -e WITH_SAMPLE_DATA=yes --env-file pg.env -p 5432:5432 pigeosolutions/hyfaa-postgis:10-3.1
```
But it is advised to use the docker-compose config from the parent repo [hyfaa-mgb-platform](https://github.com/OMP-IRD/hyfaa-mgb-platform).

## DB documentation

In the doc folder, you have some documentation about the hyfaa database:
* [Database structure](doc/database-structure.md)
* [Database Usage](doc/database-usage.md)