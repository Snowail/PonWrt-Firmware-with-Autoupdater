include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ponwrt-update
PKG_VERSION:=1.2.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ponwrt-update
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=PonWrt update backend for the existing flash page
  DEPENDS:=+luci-base +luci-mod-system +curl +jsonfilter +ca-bundle
endef

define Build/Compile
endef

define Package/luci-app-ponwrt-update/conffiles
/etc/ponwrt-update.interval
endef

# root/ is assembled from the canonical overlay before package metadata scanning.
define Package/luci-app-ponwrt-update/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults $(1)/www/luci-static/resources/ponwrt
	$(INSTALL_CONF) ./root/etc/ponwrt-update.interval $(1)/etc/
	$(INSTALL_BIN) ./root/etc/uci-defaults/92-ponwrt-update-schedule $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./root/www/luci-static/resources/ponwrt/notice.js $(1)/www/luci-static/resources/ponwrt/
	$(INSTALL_BIN) ./root/usr/bin/ponwrt-update-check $(1)/usr/bin/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-ponwrt-update.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-ponwrt-update))
