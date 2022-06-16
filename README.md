# Raincell 
This is the parent repo of the raincell demonstration portal.

## Build
You should be able to build the needed applications using docker-compose:
```bash
docker-compose build
```

## Run the apps
### Dev mode (localhost)
To start them in development mode, you can simply run
```bash
docker-compose up -d
```
Both `docker-compose.yml` and `docker-compose.override.yml` will be applied. Each service will open a port (5433, 8000, 7800). There is no reverse-proxy in front of them.
The available services are
- potgis DB on localhost:5433
- backend API. Swagger UI at http://localhost:8000/api/schema/swagger-ui/
- vector tiles service, at http://localhost:7800/tiles/. The interesting layer being the function `rain_cells_for_date`

### Production mode

To start them in production mode, the docker-compose.prod.yml applies a few modifications. Mostly, it is assuming that you have a [traefik reverse proxy](https://github.com/OMP-IRD/traefik-proxy) already running on the server and will configure the services to be exposed through this proxy.
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```


### importing dataYou can either import the sample dataset directly using the DB dump, or import your data using the app's import commands. 
- _**Using the DB dump, for a quick setup**_:
  If on dev mode, the database's port is binded to localhost, so if you have psql client installed on your computer, you can run
  ```
  gunzip < sample_data/cameroun/raincell_samples.sql.gz | psql -U postgres -d raincell -h localhost -p 5433 
  ```
- **Using the app's import tools**:
  - Import the mask netcdf file (defines the grid cells to be served)
  ```bash
  # Import the geospatial grid cells, using the netcdf mask
  docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec backend \
    /app/manage.py raincell_generate_cells /sample_data/cameroun/Raincell_masque_Cameroun.nc
  ```
    
  - Import some raincell netcdf data. You can either use `manage.py raincell_import_file` command, to import just one file, 
  or `manage.py raincell_batch_import` to import all files from a folder. For instance
  ```bash
  # Batch import
  docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec backend \
    /app/manage.py raincell_batch_import /sample_data/cameroun/samples/
  # or single file import
  #docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec backend \
  #   /app/manage.py raincell_import_file /sample_data/cameroun/samples/20211003_2355_Raincell_Cameroun_InvRainResol-2.5km.nc.aux.xml
  ```

  - alternatively, **you can generate some fake data** (*but you will still need to have generated the cells, see the previous step*):
  ```bash
  # Generate fake data
  docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec backend \
    /app/manage.py raincell_generate_fake_data --verbose --overwrite_existing 2022-05-01 2022-06-14
  ```

## About Raincell
Raincell is a project piloted by OMP-IRD, aiming to determine near real-time rain data, based on cell-towers' data. 
More about Raincell: 

Links: 
- TODO: link to informational website
- https://rapport.ird.fr/2015/fr/defis-solutions/risques/telephonie.html