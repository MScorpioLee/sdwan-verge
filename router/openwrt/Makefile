include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sdwan-verge
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Leslie <leslie@example.local>
PKG_LICENSE:=MIT
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-sdwan-verge
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=SD-WAN Verge router manager
  DEPENDS:=+luci-base +rpcd +uci +dnsmasq +ip-tiny
endef

define Package/luci-app-sdwan-verge/description
LuCI application and shell core for applying SD-WAN Verge half-route
acceleration and optional dnsmasq DNS settings on OpenWrt or iStoreOS.
endef

define Build/Compile
endef

define Package/luci-app-sdwan-verge/conffiles
/etc/config/sdwan_verge
endef

define Package/luci-app-sdwan-verge/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/sdwan_verge $(1)/etc/config/sdwan_verge
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/sdwan-verge $(1)/etc/init.d/sdwan-verge
	$(INSTALL_DIR) $(1)/usr/libexec/sdwan-verge
	$(INSTALL_BIN) ./files/usr/libexec/sdwan-verge/sdwan-verge-core $(1)/usr/libexec/sdwan-verge/sdwan-verge-core
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-sdwan-verge.json $(1)/usr/share/luci/menu.d/luci-app-sdwan-verge.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json $(1)/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/sdwan-verge
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/sdwan-verge/status.js $(1)/www/luci-static/resources/view/sdwan-verge/status.js
endef

$(eval $(call BuildPackage,luci-app-sdwan-verge))
