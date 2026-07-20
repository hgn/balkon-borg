// Great-circle math, so every client does not have to repeat it.
//
// The contract says borgd computes dist_km and bearing_deg for each aircraft
// relative to the balcony. The app has a fallback for the case where it gets neither,
// but this is where the numbers should come from: one place, one home coordinate, and
// clients that only draw.
package main

import "math"

const earthRadiusKM = 6371.0

// DistanceKM is the great-circle distance between two coordinates (haversine).
func DistanceKM(lat1, lon1, lat2, lon2 float64) float64 {
	φ1, φ2 := rad(lat1), rad(lat2)
	dφ, dλ := rad(lat2-lat1), rad(lon2-lon1)

	a := math.Sin(dφ/2)*math.Sin(dφ/2) +
		math.Cos(φ1)*math.Cos(φ2)*math.Sin(dλ/2)*math.Sin(dλ/2)
	return 2 * earthRadiusKM * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// BearingDeg is the initial compass bearing from the first point to the second, 0 = due
// north, clockwise. That is the angle the app's radar places blips at.
func BearingDeg(lat1, lon1, lat2, lon2 float64) float64 {
	φ1, φ2 := rad(lat1), rad(lat2)
	dλ := rad(lon2 - lon1)

	y := math.Sin(dλ) * math.Cos(φ2)
	x := math.Cos(φ1)*math.Sin(φ2) - math.Sin(φ1)*math.Cos(φ2)*math.Cos(dλ)
	deg := deg(math.Atan2(y, x))
	if deg < 0 {
		deg += 360
	}
	return deg
}

func rad(d float64) float64 { return d * math.Pi / 180 }
func deg(r float64) float64 { return r * 180 / math.Pi }
