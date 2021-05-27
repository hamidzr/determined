package api

import (
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

// CORSWithTargetedOrigin builds on labstack/echo CORS by dynamically setting the origin header to
// the request's origin.
func CORSWithTargetedOrigin(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		origin := c.Request().Header.Get(echo.HeaderOrigin)
		if origin == "" {
			origin = "*"
		}
		origins := []string{origin}
		config := middleware.CORSConfig{AllowOrigins: origins, AllowCredentials: true}
		return middleware.CORSWithConfig(config)(next)(c)
	}
}

func isStale(c echo.Context, key string) (isStale bool) {
	ifNoneMatch := c.Request().Header.Get("If-None-Match")
	c.Response().Header().Add("Etag", key)
	return !(ifNoneMatch != "" && ifNoneMatch == key)
}

// RespondWithFile respons to a file request while handling etags for caching.
func RespondWithFile(c echo.Context, absFilePath string) error {
	// TODO generate etag
	key := absFilePath
	if isStale(c, key) {
		// normal response processing
		return c.File(absFilePath)
	}
	return c.String(304, "")
}
