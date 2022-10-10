{
  imports = [
    {
      boot.kernelModules = ["dm_multipath" "dm_round_robin" "ipmi_watchdog"];
      services.openssh.enable = true;
      system.stateVersion = "22.05";
    }
    {
      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "ahci"
        "usbhid"
        "sd_mod"
      ];

      boot.kernelModules = ["kvm-intel"];
      boot.kernelParams = ["console=ttyS1,115200n8"];
      boot.extraModulePackages = [];
    }
    (
      {lib, ...}: {
        boot.loader.grub.extraConfig = ''
          serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
          terminal_output serial console
          terminal_input serial console
        '';
        nix.maxJobs = lib.mkDefault 16;
      }
    )
    {
      swapDevices = [
        {
          device = "/dev/disk/by-id/ata-Micron_5300_MTFDDAK480TDT_21022D16CB97-part3";
        }
      ];

      fileSystems = {
        "/boot" = {
          device = "/dev/disk/by-id/ata-Micron_5300_MTFDDAK480TDT_21022D16CB97-part2";
          fsType = "ext4";
        };

        "/" = {
          device = "zpool/root";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/nix" = {
          device = "zpool/nix";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/var" = {
          device = "zpool/var";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/cache" = {
          device = "zpool/cache";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/var/lib/nomad" = {
          device = "zpool/nomad";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/var/lib/containers" = {
          device = "zpool/containers";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/var/lib/docker" = {
          device = "zpool/docker";
          fsType = "zfs";
          options = ["defaults"];
        };

        "/home" = {
          device = "zpool/home";
          fsType = "zfs";
          options = ["defaults"];
        };
      };

      boot.loader.grub.devices = ["/dev/disk/by-id/ata-Micron_5300_MTFDDAK480TDT_21022D16CB97"];
    }
    {networking.hostId = "d395c5e8";}
    (
      {modulesPath, ...}: {
        networking.hostName = "test";
        networking.useNetworkd = true;

        systemd.network.networks."40-bond0" = {
          matchConfig.Name = "bond0";
          linkConfig = {
            RequiredForOnline = "carrier";
            MACAddress = "b8:ce:f6:0b:67:fc";
          };
          networkConfig.LinkLocalAddressing = "no";
          dns = [
            "147.75.207.207"
            "147.75.207.208"
          ];
        };

        boot.extraModprobeConfig = "options bonding max_bonds=0";
        systemd.network.netdevs = {
          "10-bond0" = {
            netdevConfig = {
              Kind = "bond";
              Name = "bond0";
            };
            bondConfig = {
              Mode = "802.3ad";
              LACPTransmitRate = "fast";
              TransmitHashPolicy = "layer3+4";
              DownDelaySec = 0.2;
              UpDelaySec = 0.2;
              MIIMonitorSec = 0.1;
            };
          };
        };

        systemd.network.networks."30-enp2s0f0np0" = {
          matchConfig = {
            Name = "enp2s0f0np0";
            PermanentMACAddress = "b8:ce:f6:0b:67:fc";
          };
          networkConfig.Bond = "bond0";
        };

        systemd.network.networks."30-enp2s0f1np1" = {
          matchConfig = {
            Name = "enp2s0f1np1";
            PermanentMACAddress = "b8:ce:f6:0b:67:fd";
          };
          networkConfig.Bond = "bond0";
        };

        systemd.network.networks."40-bond0".addresses = [
          {
            addressConfig.Address = "145.40.96.133/31";
          }
          {
            addressConfig.Address = "2604:1380:4601:ba00::1/127";
          }
          {
            addressConfig.Address = "10.12.100.1/31";
          }
        ];
        systemd.network.networks."40-bond0".routes = [
          {
            routeConfig.Gateway = "145.40.96.132";
          }
          {
            routeConfig.Gateway = "2604:1380:4601:ba00::";
          }
          {
            routeConfig.Gateway = "10.12.100.0";
          }
        ];
      }
    )
  ];
}
