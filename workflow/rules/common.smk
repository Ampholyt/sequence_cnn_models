################################
#### Global functions       ####
################################
import os

def getScript(name):
    return os.path.join(os.path.dirname(workflow.main_snakefile), 'scripts', name)


from snakemake.utils import validate
import pandas as pd


# this container defines the underlying OS for each job when using the workflow
# with --use-conda --use-singularity
container: "docker://continuumio/miniconda3"


##### load config and sample sheets #####

# preferrred to use --configfile instead of hard-coded config file
# configfile: "config/config.yaml"


def isRegression():
    """
    Check if we are running a regression test.
    """
    return config["regression"]


validate(config, schema="../schemas/config.schema.yaml")

if not isRegression():
    samples = pd.read_csv(config["samples"], sep="\t").set_index("sample", drop=False)
    samples.index.names = ["sample_id"]
    validate(samples, schema="../schemas/samples.schema.yaml")

    tests = pd.read_csv(config["tests"], sep="\t").set_index("test", drop=False)
    tests.index.names = ["test_id"]
    validate(tests, schema="../schemas/tests.schema.yaml")


def getWrapper(wrapper):
    """
    Get directory for snakemake wrappers.
    """
    return "file:%s/wrapper.py" % (getWrapperPath(wrapper))


def getWrapperPath(file):
    """
    Get directory for snakemake wrappers.
    """
    return os.path.abspath(os.path.join(config["wrapper_directory"], file))


def isPretrained():
    """
    Check if we are using a pretrained model.
    """
    return config["training"]["model"] == "file" or isPretrainedLegnet()


def hasFolds():
    """
    Check if we are using cross-validation.
    """
    return config["training"]["folds"] > 1


def getTestFolds(bins):
    """
    Get test folds for a given number of bins. Multiplys it by the number of validation folds!
    """
    output = []
    if hasFolds():
        for i in range(1, bins + 1):
            output += [i] * (bins - 1)
    else:
        output = [1]
    return output


def getValidationFolds(bins):
    """
    Get validation folds for a given number of bins.
    """
    output = []
    for i in range(1, bins + 1):
        possible = list(range(1, bins + 1))
        possible.remove(i)
        output += possible

    return output


def getValidationFoldsForTest(test_fold, bins):
    output = list(range(1, bins + 1))
    if hasFolds():
        output.remove(int(test_fold))
    return output


def isPretrainedLegnet():
    """
    Check if it is configured that the model is a pretrained legnet model
    """
    return config["training"]["model"] == "legnet"


def getModelPath(testFold=1, validationFold=1):
    """
    Get path to model.
    """
    if isPretrained():
        if not hasFolds():
            return {
                "model": config["training"]["model_files"]["model"],
                "weights": config["training"]["model_files"]["weights"],
            }
        else:
            return {
                "model": config["training"]["model_files"]["model"][int(testFold)][
                    int(validationFold)
                ],
                "weights": config["training"]["model_files"]["weights"][int(testFold)][
                    int(validationFold)
                ],
            }
    elif not isRegression():
        return {
            "model": "results/training/model.classification.json",
            "weights": "results/training/weights.classification.h5",
        }
    else:
        return {
            "model": "results/training/model.regression.{test_fold}.{validation_fold}.json",
            "weights": "results/training/weights.regression.{test_fold}.{validation_fold}.h5",
        }


def getTestSequences(test_sequence_type):
    """
    Get test sequences.
    """
    if isPretrained():
        return config["input"]["fasta"]
    elif test_sequence_type != "ism":
        return config["input"]["fasta"][test_sequence_type]
    else:
        return "results/model_interpretation/input/regression.test.{test_fold}.{validation_fold}.fa.gz"


def getlabelsForRename():
    """
    rename prediction columns to get a nice output
    """
    out = {}
    for i, name in enumerate(config["prediction"]["output_names"]):
        out[name] = "%s_MPRA" % name
        out["%d.MEAN_prediction" % i] = "%s_MPRAnn" % name
        out["%d.STD_prediction" % i] = "%s_STD_MPRAnn" % name
    return out

def getColumnsForMean(test_fold):
    validation_folds = getValidationFoldsForTest(test_fold, config["training"]["folds"])
    return np.array(
        expand(
            "{fold}.{output}",
            fold=validation_folds,
            output=range(0, config["prediction"]["output_size"]),
        )
    ).reshape(len(validation_folds), config["prediction"]["output_size"])


def getPredictionTestFile(test_name):
    if isFastaFile(test_name):
        return config["prediction"]["samples"][test_name]["fasta"]
    else:
        return "results/test_predictions/inputs/{test_name}.tsv.gz"


def isFastaFile(test_name):
    return "labels" not in config["prediction"]["samples"][test_name]


######################
# all input methods #
#####################


def getRegressionTraining_all():
    """
    Get all training and output data for regression.
    """
    output = []
    if isRegression() and not isPretrained():
        output = ["results/regression_input/regression.tsv.gz"]

        output.extend(
            expand(
                "results/regression_input/regression.training.{test_fold}.{validation_fold}.tsv.gz",
                zip,
                test_fold=getTestFolds(config["training"]["folds"]),
                validation_fold=getValidationFolds(config["training"]["folds"]),
            )
        )
        output.extend(
            expand(
                "results/regression_input/regression.validation.{test_fold}.{validation_fold}.tsv.gz",
                zip,
                test_fold=getTestFolds(config["training"]["folds"]),
                validation_fold=getValidationFolds(config["training"]["folds"]),
            )
        )
        output.extend(
            expand(
                "results/regression_input/regression.test.{test_fold}.{validation_fold}.tsv.gz",
                zip,
                test_fold=getTestFolds(config["training"]["folds"]),
                validation_fold=getValidationFolds(config["training"]["folds"]),
            )
        )
        output.extend(
            expand(
                "results/training/model.regression.{test_fold}.{validation_fold}.json",
                zip,
                test_fold=getTestFolds(config["training"]["folds"]),
                validation_fold=getValidationFolds(config["training"]["folds"]),
            )
        )
    return output
