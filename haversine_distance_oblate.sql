-- haversine distance UDF for oblate spheroid shape

CREATE OR REPLACE FUNCTION public.haversine_distance_oblate(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
 RETURNS double precision
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Earth's radii in kilometers (equatorial and polar)
    equatorialRadius float := 6378.137;
    polarRadius float := 6356.7523;
    x float := RADIANS((lat2 - lat1) * equatorialRadius);
    y float := RADIANS((lon2 - lon1) * equatorialRadius * COS(RADIANS(lat1)));

    -- Calculate the adjusted radius using the latitude and Earth's oblate spheroid shape
    radius float := SQRT(
        (POW(POW(equatorialRadius * COS(RADIANS(lat1)), 2), 2) +
        POW(POW(polarRadius * SIN(RADIANS(lat1)), 2), 2)) /
        (POW(equatorialRadius * COS(RADIANS(lat1)), 2) +
        POW(polarRadius * SIN(RADIANS(lat1)), 2))
    );
BEGIN
    -- Calculate the distance on the surface of the oblate spheroid using the adjusted radius and Pythagorean theorem.
    RETURN SQRT(x * x + y * y) * radius;
END;
$function$;

---------------------------------------
---------------------------------------


-- Existing haversine_distance UDF
SELECT pg_get_functiondef('haversine_distance'::regproc);

-- alternate way
SELECT prosrc
FROM pg_proc
WHERE proname = 'haversine_distance';

-------------

-- result 1
CREATE OR REPLACE FUNCTION public.haversine_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
 RETURNS double precision
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- here we calculate the difference in latitudes, multiply it by 111.19
    -- to convert it to kilometers (as each degree is approximately 111.19 km on Earth's surface).
    x float = 111.19 * (lat2 - lat1);

    -- here we calculate the difference in longitudes and multiply it by 111.19
    -- and the cosine of the first latitude. The cosine factor adjusts for the fact that
    -- the distance covered by a degree of longitude decreases as you move away from the equator.
    -- the latitude is divided by 57.3 to convert it from degrees to radians because the COS function
    -- in SQL operates on radians, not degrees.
    y float = 111.19 * (lon2 - lon1) * COS(lat1 / 57.3);
BEGIN
    -- finally, the Pythagorean theorem (sqrt(x^2 + y^2)) is used to calculate the straight-line distance
    -- (in kilometers) between the two points (x,y). This is the "Euclidean" distance on the surface of the Earth.
    -- it's a simplification because it doesn't fully account for the Earth's curvature,
    -- but it's often accurate enough for short distances.
    RETURN SQRT(x * x + y * y);
END;
$function$

-------------

-- result 2
prosrc
|
DECLARE
    -- here we calculate the difference in latitudes, multiply it by 111.19
    -- to convert it to kilometers (as each degree is approximately 111.19 km on Earth's surface).
    x float = 111.19 * (lat2 - lat1);

    -- here we calculate the difference in longitudes and multiply it by 111.19
    -- and the cosine of the first latitude. The cosine factor adjusts for the fact that
    -- the distance covered by a degree of longitude decreases as you move away from the equator.
    -- the latitude is divided by 57.3 to convert it from degrees to radians because the COS function
    -- in SQL operates on radians, not degrees.
    y float = 111.19 * (lon2 - lon1) * COS(lat1 / 57.3);
BEGIN
    -- finally, the Pythagorean theorem (sqrt(x^2 + y^2)) is used to calculate the straight-line distance
    -- (in kilometers) between the two points (x,y). This is the "Euclidean" distance on the surface of the Earth.
    -- it's a simplification because it doesn't fully account for the Earth's curvature,
    -- but it's often accurate enough for short distances.
    RETURN SQRT(x * x + y * y);
END;
 |

---------------------------------------
---------------------------------------
