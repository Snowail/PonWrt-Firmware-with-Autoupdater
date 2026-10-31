include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ponwrt-update
PKG_VERSION:=1.1.0
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

# root/ is assembled from the canonical overlay before package metadata scanning.
# Install only the backend and ACL; the existing flash.js is patched separately.
define Package/luci-app-ponwrt-update/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/share/rpcd/acl.d
	$(INSTALL_BIN) ./root/usr/bin/ponwrt-update-check $(1)/usr/bin/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-ponwrt-update.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-ponwrt-update))
