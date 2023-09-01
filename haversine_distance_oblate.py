# haversine_distance_oblate calculation script
# author: ranga4all1
# created on: 09/01/2023
# Last updated: 09/01/2023

# Usage example: python haversine_distance_oblate.py 33.9416 -118.4085 40.6413 -73.7781


import math
import sys


def haversine_distance_oblate(lat1, lon1, lat2, lon2):
    # Earth's radii in kilometers (equatorial and polar)
    equatorial_radius = 6378.137
    polar_radius = 6356.7523

    # Convert degrees to radians
    lat1 = math.radians(lat1)
    lon1 = math.radians(lon1)
    lat2 = math.radians(lat2)
    lon2 = math.radians(lon2)

    # Calculate the differences in latitudes and longitudes
    delta_lat = lat2 - lat1
    delta_lon = lon2 - lon1

    # Calculate the adjusted radius using the latitude and Earth's oblate spheroid shape
    radius = math.sqrt(
        (
            (equatorial_radius * math.cos(lat1)) ** 2
            + (polar_radius * math.sin(lat1)) ** 2
        )
        / (
            (equatorial_radius * math.cos(lat1)) ** 2
            + (polar_radius * math.sin(lat1)) ** 2
        )
    )

    # Calculate the differences in radians
    x = delta_lat * equatorial_radius
    y = delta_lon * equatorial_radius * math.cos(lat1)

    # Calculate the distance using the adjusted radius and Pythagorean theorem
    distance = math.sqrt(x**2 + y**2) * radius

    return distance


def main():
    # Check if there are enough command-line arguments
    if len(sys.argv) != 5:
        print("Usage: python haversine_distance_oblate.py lat1 lon1 lat2 lon2")
        return

    # Parse command-line arguments
    lat1, lon1, lat2, lon2 = map(float, sys.argv[1:])

    # Calculate the distance
    distance = haversine_distance_oblate(lat1, lon1, lat2, lon2)
    print(
        f"Distance between the two given locations on oblate earth is: {distance:.2f} km"
    )


if __name__ == "__main__":
    main()
