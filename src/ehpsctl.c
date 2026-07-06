#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/hidraw.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define ELAN_VENDOR 0x04f3
#define DEFAULT_CONFIG "/etc/z13-tuned/ehps.config"

static int verbose;

struct ehps_config {
    bool haptic_feedback;
    int feedback_state;
    int click_force;
    bool topzone_post_button;
    int post_button_force;
    unsigned char raw[6];
};

static const char *force_name(int value)
{
    static const char *names[] = { "low", "medium", "high" };

    if (value < 0 || value > 2) {
        return "unknown";
    }
    return names[value];
}

static int parse_bool(const char *value, bool *out)
{
    if (strcmp(value, "on") == 0 || strcmp(value, "yes") == 0 ||
        strcmp(value, "true") == 0 || strcmp(value, "1") == 0 ||
        strcmp(value, "enable") == 0 || strcmp(value, "enabled") == 0) {
        *out = true;
        return 0;
    }
    if (strcmp(value, "off") == 0 || strcmp(value, "no") == 0 ||
        strcmp(value, "false") == 0 || strcmp(value, "0") == 0 ||
        strcmp(value, "disable") == 0 || strcmp(value, "disabled") == 0) {
        *out = false;
        return 0;
    }

    return -1;
}

static int parse_force(const char *value)
{
    if (strcmp(value, "low") == 0 || strcmp(value, "0") == 0) {
        return 0;
    }
    if (strcmp(value, "medium") == 0 || strcmp(value, "med") == 0 ||
        strcmp(value, "1") == 0) {
        return 1;
    }
    if (strcmp(value, "high") == 0 || strcmp(value, "2") == 0) {
        return 2;
    }

    return -1;
}

static int parse_level(const char *value, int min, int max)
{
    char *end = NULL;
    long parsed;

    errno = 0;
    parsed = strtol(value, &end, 0);
    if (errno || !end || *end || parsed < min || parsed > max) {
        return -1;
    }

    return (int)parsed;
}

static int hid_set_feature(int fd, const unsigned char report[5])
{
    unsigned char buf[5];
    memcpy(buf, report, sizeof(buf));
    if (verbose) {
        fprintf(stderr, "setfeature: %02x %02x %02x %02x %02x\n",
                buf[0], buf[1], buf[2], buf[3], buf[4]);
    }
    return ioctl(fd, HIDIOCSFEATURE(sizeof(buf)), buf);
}

static int elan_read_cmd(int fd, uint16_t cmd, uint16_t *value)
{
    unsigned char set_report[5] = {
        0x0d, 0x05, 0x03, cmd & 0xff, cmd >> 8
    };
    unsigned char get_report[5] = { 0x0d, 0, 0, 0, 0 };

    if (hid_set_feature(fd, set_report) < 0) {
        return -1;
    }
    if (ioctl(fd, HIDIOCGFEATURE(sizeof(get_report)), get_report) < 0) {
        return -1;
    }
    if (verbose) {
        fprintf(stderr, "getfeature: %02x %02x %02x %02x %02x\n",
                get_report[0], get_report[1], get_report[2], get_report[3], get_report[4]);
    }
    if (get_report[1] != set_report[3] || get_report[2] != set_report[4]) {
        errno = EPROTO;
        return -1;
    }

    *value = (uint16_t)get_report[3] | ((uint16_t)get_report[4] << 8);
    return 0;
}

static int elan_write_cmd(int fd, uint16_t cmd, uint16_t value)
{
    unsigned char report[5] = {
        0x0d, cmd & 0xff, cmd >> 8, value & 0xff, value >> 8
    };

    return hid_set_feature(fd, report);
}

static int elan_write_verify(int fd, uint16_t cmd, uint16_t value)
{
    uint16_t actual = 0;

    for (int attempt = 0; attempt < 3; attempt++) {
        if (elan_write_cmd(fd, cmd, value) >= 0) {
            usleep(500);
            if (elan_read_cmd(fd, cmd, &actual) == 0 && actual == value) {
                return 0;
            }
        }
        usleep(20000);
    }

    fprintf(stderr, "verify failed for cmd 0x%04x: wanted 0x%04x got 0x%04x\n",
            cmd, value, actual);
    errno = EIO;
    return -1;
}

static int open_touchpad(void)
{
    DIR *dir = opendir("/dev");
    struct dirent *ent;

    if (!dir) {
        perror("opendir /dev");
        return -1;
    }

    while ((ent = readdir(dir))) {
        char path[256];
        struct hidraw_devinfo info;
        int fd;

        if (strncmp(ent->d_name, "hidraw", 6) != 0) {
            continue;
        }

        if (snprintf(path, sizeof(path), "/dev/%s", ent->d_name) >= (int)sizeof(path)) {
            continue;
        }
        fd = open(path, O_RDWR | O_NONBLOCK);
        if (fd < 0) {
            continue;
        }

        memset(&info, 0, sizeof(info));
        if (ioctl(fd, HIDIOCGRAWINFO, &info) == 0 && info.vendor == ELAN_VENDOR) {
            uint16_t function = 0;
            uint16_t family = 0;

            if (elan_read_cmd(fd, 0x0101, &function) == 0 &&
                elan_read_cmd(fd, 0x0103, &family) == 0 &&
                function == 0x000d && (family >> 8) == 0x13) {
                printf("using %s (VID %04x PID %04x, function 0x%04x family 0x%04x)\n",
                       path, info.vendor, info.product, function, family);
                closedir(dir);
                return fd;
            }

            if (verbose) {
                fprintf(stderr,
                        "skip %s (VID %04x PID %04x, function 0x%04x family 0x%04x)\n",
                        path, info.vendor, info.product, function, family);
            }
        }

        close(fd);
    }

    closedir(dir);
    errno = ENODEV;
    return -1;
}

static int set_haptic_feedback(int fd, bool enabled)
{
    uint16_t value;

    if (elan_read_cmd(fd, 0x03a1, &value) < 0) {
        return -1;
    }

    if (enabled) {
        value |= 0x0100;
    } else {
        value &= 0xfeff;
    }

    return elan_write_cmd(fd, 0x03a1, value);
}

static int set_topzone_post_button(int fd, bool enabled)
{
    uint16_t value;

    if (elan_read_cmd(fd, 0x03a1, &value) < 0) {
        return -1;
    }

    if (enabled) {
        value |= 0x0002;
    } else {
        value &= 0xfffd;
    }

    return elan_write_cmd(fd, 0x03a1, value);
}

static int set_feedback_state(int fd, int level)
{
    static const uint16_t values[] = { 0x0000, 0x5050, 0x4040, 0x3030, 0x2020 };

    if (level < 0 || level >= (int)(sizeof(values) / sizeof(values[0]))) {
        errno = EINVAL;
        return -1;
    }

    return elan_write_verify(fd, 0x03ab, values[level]);
}

static int set_click_force(int fd, int level)
{
    static const uint16_t push[] = { 0x007a, 0x00a0, 0x00c0 };
    static const uint16_t release[] = { 0x0062, 0x0080, 0x009a };

    if (level < 0 || level >= (int)(sizeof(push) / sizeof(push[0]))) {
        errno = EINVAL;
        return -1;
    }

    return elan_write_verify(fd, 0x03a2, push[level]) ||
           elan_write_verify(fd, 0x03a3, release[level]) ||
           elan_write_verify(fd, 0x03a4, 0x003c);
}

static int set_post_button_force(int fd, int level)
{
    static const uint16_t push[] = { 0x0050, 0x006e, 0x008c };
    static const uint16_t release[] = { 0x003c, 0x0042, 0x0054 };

    if (level < 0 || level >= (int)(sizeof(push) / sizeof(push[0]))) {
        errno = EINVAL;
        return -1;
    }

    return elan_write_verify(fd, 0x03a9, push[level]) ||
           elan_write_verify(fd, 0x03aa, release[level]);
}

static void config_to_raw(const struct ehps_config *cfg, unsigned char raw[6])
{
    raw[0] = 0x15;
    raw[1] = cfg->haptic_feedback ? 0x16 : 0x15;
    raw[2] = 0x15 + cfg->feedback_state;
    raw[3] = 0x15 + cfg->click_force;

    raw[4] = cfg->topzone_post_button ? 0x16 : 0x15;
    raw[5] = 0x15 + cfg->post_button_force;
}

static int raw_to_config(const unsigned char raw[6], struct ehps_config *cfg)
{
    if (raw[0] != 0x15 ||
        (raw[1] != 0x15 && raw[1] != 0x16) ||
        raw[2] < 0x15 || raw[2] > 0x19 ||
        raw[3] < 0x15 || raw[3] > 0x17 ||
        raw[4] < 0x15 || raw[4] > 0x17 ||
        raw[5] < 0x15 || raw[5] > 0x17) {
        errno = EINVAL;
        return -1;
    }

    memcpy(cfg->raw, raw, sizeof(cfg->raw));
    cfg->haptic_feedback = raw[1] == 0x16;
    cfg->feedback_state = raw[2] - 0x15;
    cfg->click_force = raw[3] - 0x15;
    cfg->topzone_post_button = raw[4] != 0x15;
    cfg->post_button_force = raw[5] - 0x15;
    return 0;
}

static int load_config(const char *path, struct ehps_config *cfg)
{
    unsigned char raw[6];
    FILE *fp = fopen(path, "rb");

    if (!fp) {
        perror(path);
        return -1;
    }
    if (fread(raw, 1, sizeof(raw), fp) != sizeof(raw)) {
        fprintf(stderr, "%s: expected 6 config bytes\n", path);
        fclose(fp);
        return -1;
    }
    fclose(fp);

    if (raw_to_config(raw, cfg) < 0) {
        fprintf(stderr, "%s: unsupported config bytes: %02x %02x %02x %02x %02x %02x\n",
                path, raw[0], raw[1], raw[2], raw[3], raw[4], raw[5]);
        return -1;
    }

    return 0;
}

static int save_config(const char *path, const struct ehps_config *cfg)
{
    unsigned char raw[6];
    FILE *fp;

    config_to_raw(cfg, raw);
    fp = fopen(path, "wb");
    if (!fp) {
        perror(path);
        return -1;
    }
    if (fwrite(raw, 1, sizeof(raw), fp) != sizeof(raw)) {
        perror(path);
        fclose(fp);
        return -1;
    }
    fclose(fp);
    return 0;
}

static void print_config(const struct ehps_config *cfg)
{
    printf("raw: %02x %02x %02x %02x %02x %02x\n",
           cfg->raw[0], cfg->raw[1], cfg->raw[2],
           cfg->raw[3], cfg->raw[4], cfg->raw[5]);
    printf("haptic-feedback: %s\n", cfg->haptic_feedback ? "on" : "off");
    printf("feedback-state: %d\n", cfg->feedback_state);
    printf("click-force: %s\n", force_name(cfg->click_force));
    printf("topzone-post-button: %s\n", cfg->topzone_post_button ? "on" : "off");
    printf("post-button-force: %s\n", force_name(cfg->post_button_force));
    puts("note: vendor startup ignores byte 6; ehpsctl uses it for independent post-button force");
}

static int apply_config_values(int fd, const struct ehps_config *cfg)
{
    printf("config: %02x %02x %02x %02x %02x %02x\n",
           cfg->raw[0], cfg->raw[1], cfg->raw[2],
           cfg->raw[3], cfg->raw[4], cfg->raw[5]);

    if (set_haptic_feedback(fd, cfg->haptic_feedback) < 0 ||
        set_feedback_state(fd, cfg->feedback_state) < 0 ||
        set_click_force(fd, cfg->click_force) < 0 ||
        set_topzone_post_button(fd, cfg->topzone_post_button) < 0 ||
        set_post_button_force(fd, cfg->post_button_force) < 0) {
        perror("apply setting");
        return -1;
    }

    return 0;
}

static void set_default_config(struct ehps_config *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    cfg->haptic_feedback = true;
    cfg->feedback_state = 4;
    cfg->click_force = 0;
    cfg->topzone_post_button = true;
    cfg->post_button_force = 1;
    config_to_raw(cfg, cfg->raw);
}

static void usage(FILE *out)
{
    fprintf(out,
            "usage:\n"
            "  ehpsctl [apply] [--config PATH] [-v]\n"
            "  ehpsctl show [--config PATH]\n"
            "  ehpsctl set [options] [--config PATH] [--no-apply] [-v]\n"
            "\n"
            "options for set:\n"
            "  --haptic-feedback on|off\n"
            "  --feedback-state 0..4\n"
            "  --click-force low|medium|high\n"
            "  --topzone-post-button on|off\n"
            "  --post-button-force low|medium|high\n"
            "\n"
            "examples:\n"
            "  sudo ehpsctl set --click-force high --feedback-state 3\n"
            "  ehpsctl show\n"
            "  sudo ehpsctl apply\n");
}

static int open_device_or_die(void)
{
    int fd;

    if (geteuid() != 0) {
        fprintf(stderr, "ehpsctl must run as root to open /dev/hidraw*\n");
        return -1;
    }

    fd = open_touchpad();
    if (fd < 0) {
        perror("could not find ELAN haptic touchpad");
    }

    return fd;
}

static int command_apply(const char *config_path)
{
    struct ehps_config cfg;
    int fd;
    int rc;

    if (load_config(config_path, &cfg) < 0) {
        return 1;
    }

    fd = open_device_or_die();
    if (fd < 0) {
        return 1;
    }

    rc = apply_config_values(fd, &cfg);
    close(fd);

    if (rc == 0) {
        puts("settings applied");
        return 0;
    }

    return 1;
}

static int command_show(const char *config_path)
{
    struct ehps_config cfg;

    if (load_config(config_path, &cfg) < 0) {
        return 1;
    }

    print_config(&cfg);
    return 0;
}

static int command_set(int argc, char **argv, int start, const char *config_path, bool apply)
{
    struct ehps_config cfg;
    bool changed = false;

    if (access(config_path, F_OK) != 0) {
        set_default_config(&cfg);
    } else if (load_config(config_path, &cfg) < 0) {
        fprintf(stderr, "using defaults because %s could not be loaded\n", config_path);
        set_default_config(&cfg);
    }

    for (int i = start; i < argc; i++) {
        const char *arg = argv[i];
        const char *value;
        bool enabled;
        int parsed;

        if (strcmp(arg, "--config") == 0 || strcmp(arg, "-c") == 0 ||
            strcmp(arg, "--no-apply") == 0 || strcmp(arg, "-v") == 0 ||
            strcmp(arg, "--verbose") == 0) {
            if ((strcmp(arg, "--config") == 0 || strcmp(arg, "-c") == 0) && i + 1 < argc) {
                i++;
            }
            continue;
        }

        if (i + 1 >= argc) {
            fprintf(stderr, "%s needs a value\n", arg);
            return 1;
        }
        value = argv[++i];

        if (strcmp(arg, "--haptic-feedback") == 0) {
            if (parse_bool(value, &enabled) < 0) {
                fprintf(stderr, "invalid haptic-feedback value: %s\n", value);
                return 1;
            }
            cfg.haptic_feedback = enabled;
        } else if (strcmp(arg, "--feedback-state") == 0) {
            parsed = parse_level(value, 0, 4);
            if (parsed < 0) {
                fprintf(stderr, "invalid feedback-state value: %s\n", value);
                return 1;
            }
            cfg.feedback_state = parsed;
        } else if (strcmp(arg, "--click-force") == 0) {
            parsed = parse_force(value);
            if (parsed < 0) {
                fprintf(stderr, "invalid click-force value: %s\n", value);
                return 1;
            }
            cfg.click_force = parsed;
        } else if (strcmp(arg, "--topzone-post-button") == 0) {
            if (parse_bool(value, &enabled) < 0) {
                fprintf(stderr, "invalid topzone-post-button value: %s\n", value);
                return 1;
            }
            cfg.topzone_post_button = enabled;
        } else if (strcmp(arg, "--post-button-force") == 0) {
            parsed = parse_force(value);
            if (parsed < 0) {
                fprintf(stderr, "invalid post-button-force value: %s\n", value);
                return 1;
            }
            cfg.post_button_force = parsed;
        } else {
            fprintf(stderr, "unknown option: %s\n", arg);
            usage(stderr);
            return 1;
        }

        changed = true;
    }

    if (!changed) {
        fprintf(stderr, "set needs at least one setting\n");
        usage(stderr);
        return 1;
    }

    config_to_raw(&cfg, cfg.raw);
    if (save_config(config_path, &cfg) < 0) {
        return 1;
    }
    printf("saved %s\n", config_path);
    print_config(&cfg);

    if (!apply) {
        return 0;
    }

    return command_apply(config_path);
}

int main(int argc, char **argv)
{
    const char *config_path = DEFAULT_CONFIG;
    const char *command = "apply";
    int command_index = 1;
    bool apply_after_set = true;

    if (argc > 1 &&
        (strcmp(argv[1], "apply") == 0 || strcmp(argv[1], "show") == 0 ||
         strcmp(argv[1], "set") == 0 || strcmp(argv[1], "help") == 0)) {
        command = argv[1];
        command_index = 2;
    }

    for (int i = command_index; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = 1;
        } else if (strcmp(argv[i], "--config") == 0 || strcmp(argv[i], "-c") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "%s needs a path\n", argv[i]);
                return 1;
            }
            config_path = argv[++i];
        } else if (strcmp(argv[i], "--no-apply") == 0) {
            apply_after_set = false;
        } else if (strcmp(command, "apply") == 0 && argv[i][0] != '-') {
            config_path = argv[i];
        }
    }

    if (strcmp(command, "help") == 0 || strcmp(command, "--help") == 0 ||
        strcmp(command, "-h") == 0) {
        usage(stdout);
        return 0;
    }
    if (strcmp(command, "show") == 0) {
        return command_show(config_path);
    }
    if (strcmp(command, "set") == 0) {
        return command_set(argc, argv, command_index, config_path, apply_after_set);
    }
    if (strcmp(command, "apply") == 0) {
        return command_apply(config_path);
    }

    fprintf(stderr, "unknown command: %s\n", command);
    usage(stderr);
    return 1;
}
